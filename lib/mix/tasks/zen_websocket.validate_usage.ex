defmodule Mix.Tasks.ZenWebsocket.ValidateUsage do
  @shortdoc "Validate code follows ZenWebsocket usage rules"

  @moduledoc """
  Validates that code follows ZenWebsocket usage rules.

  This task helps ensure that your code correctly uses ZenWebsocket's
  simplified API and follows best practices.

  ## Usage

      mix zen_websocket.validate_usage [files_or_paths]
      
  ## Options

    * `--strict` - Enable strict mode (fail on warnings)
    * `--fix` - Attempt to auto-fix simple issues
    * `--format` - Output format: `human` (default), `json`, or `github`
    
  ## Examples

      # Validate all Elixir files
      mix zen_websocket.validate_usage
      
      # Validate specific file
      mix zen_websocket.validate_usage lib/my_websocket.ex
      
      # Strict validation with GitHub Actions format
      mix zen_websocket.validate_usage --strict --format github
      
      # Auto-fix simple issues
      mix zen_websocket.validate_usage --fix
  """

  use Mix.Task

  @allowed_functions ~w(connect send_message subscribe get_state close)a

  defp common_antipatterns do
    [
      {~r/defmodule.*use\s+WebSockex/, "Don't create wrapper modules - use Client directly"},
      {~r/Process\.spawn.*Client\.connect/, "Use supervision patterns instead of manual spawning"},
      {~r/:meck|:mock|Mock\./, "Never mock WebSocket connections - use real endpoints"},
      {~r/try\s+do.*Client\.connect.*rescue/, "Don't rescue connection errors - handle {:error, reason}"},
      {~r/Client\.\w+!\(/, "ZenWebsocket doesn't have bang functions - use pattern matching"},
      {~r/defstruct.*websocket.*state/, "Don't maintain custom WebSocket state - use Client.get_state/1"},
      {~r/GenServer\.call.*timeout:\s*:infinity/, "Always specify timeouts for WebSocket operations"}
    ]
  end

  defp deprecated_patterns do
    [
      {~r/WebsockexAdapter/, "Use ZenWebsocket instead of WebsockexAdapter"},
      {~r/Websockex\./, "Migrate from Websockex to ZenWebsocket.Client"}
    ]
  end

  @impl Mix.Task
  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [
          strict: :boolean,
          fix: :boolean,
          format: :string
        ]
      )

    format = Keyword.get(opts, :format, "human")
    strict = Keyword.get(opts, :strict, false)
    fix = Keyword.get(opts, :fix, false)

    files = get_files_to_validate(files)
    issues = validate_files(files)

    if fix do
      fix_issues(issues)
    end

    report_issues(issues, format)

    if strict and issues != [] do
      System.halt(1)
    end
  end

  defp get_files_to_validate([]) do
    Path.wildcard("lib/**/*.ex") ++ Path.wildcard("test/**/*.exs")
  end

  defp get_files_to_validate(paths) do
    Enum.flat_map(paths, fn path ->
      if File.dir?(path) do
        Path.wildcard("#{path}/**/*.{ex,exs}")
      else
        [path]
      end
    end)
  end

  defp validate_files(files) do
    Enum.flat_map(files, &validate_file/1)
  end

  defp validate_file(file) do
    case File.read(file) do
      {:ok, content} ->
        lines = String.split(content, "\n")

        antipattern_issues = find_antipatterns(file, content, lines)
        deprecated_issues = find_deprecated(file, content, lines)
        api_issues = validate_api_usage(file, content, lines)

        antipattern_issues ++ deprecated_issues ++ api_issues

      {:error, _} ->
        []
    end
  end

  defp find_antipatterns(file, content, lines) do
    Enum.flat_map(common_antipatterns(), fn {pattern, message} ->
      case Regex.run(pattern, content, return: :index) do
        nil ->
          []

        [{start_idx, _length} | _] ->
          line_num = get_line_number(content, start_idx)
          line_content = Enum.at(lines, line_num - 1, "")

          [
            %{
              file: file,
              line: line_num,
              type: :antipattern,
              message: message,
              code: String.trim(line_content),
              severity: :warning
            }
          ]
      end
    end)
  end

  defp find_deprecated(file, content, lines) do
    Enum.flat_map(deprecated_patterns(), fn {pattern, message} ->
      case Regex.run(pattern, content, return: :index) do
        nil ->
          []

        [{start_idx, _length} | _] ->
          line_num = get_line_number(content, start_idx)
          line_content = Enum.at(lines, line_num - 1, "")

          [
            %{
              file: file,
              line: line_num,
              type: :deprecated,
              message: message,
              code: String.trim(line_content),
              severity: :error
            }
          ]
      end
    end)
  end

  defp validate_api_usage(file, content, lines) do
    # Find all ZenWebsocket.Client function calls
    pattern = ~r/ZenWebsocket\.Client\.(\w+)/

    pattern
    |> Regex.scan(content, return: :index)
    |> Enum.map(fn [{start_idx, _}, {func_start, func_len}] ->
      function = String.slice(content, func_start, func_len)
      func_atom = String.to_atom(function)

      if func_atom in @allowed_functions do
        nil
      else
        line_num = get_line_number(content, start_idx)
        line_content = Enum.at(lines, line_num - 1, "")

        %{
          file: file,
          line: line_num,
          type: :invalid_api,
          message: "Unknown function Client.#{function}/N - allowed: #{inspect(@allowed_functions)}",
          code: String.trim(line_content),
          severity: :error
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_line_number(content, char_index) do
    content
    |> String.slice(0, char_index)
    |> String.split("\n")
    |> length()
  end

  defp fix_issues(issues) do
    fixable = Enum.filter(issues, &fixable?/1)

    files_to_fix = Enum.group_by(fixable, & &1.file)

    Enum.each(files_to_fix, fn {file, file_issues} ->
      fix_file(file, file_issues)
    end)

    Mix.shell().info("Fixed #{length(fixable)} issues")
  end

  defp fixable?(%{type: :deprecated}), do: true
  defp fixable?(_), do: false

  defp fix_file(file, issues) do
    {:ok, content} = File.read(file)

    fixed_content =
      Enum.reduce(issues, content, fn issue, acc ->
        case issue.type do
          :deprecated ->
            acc
            |> String.replace("WebsockexAdapter", "ZenWebsocket")
            |> String.replace("Websockex.", "ZenWebsocket.Client.")

          _ ->
            acc
        end
      end)

    File.write!(file, fixed_content)
    Mix.shell().info("Fixed #{file}")
  end

  defp report_issues([], _format) do
    Mix.shell().info("✅ No issues found! Your code follows ZenWebsocket usage rules.")
  end

  defp report_issues(issues, format) do
    case format do
      "human" -> report_human(issues)
      "json" -> report_json(issues)
      "github" -> report_github(issues)
      _ -> Mix.raise("Unknown format: #{format}")
    end
  end

  defp report_human(issues) do
    Enum.each(issues, fn issue ->
      severity =
        case issue.severity do
          :error -> "ERROR"
          :warning -> "WARNING"
        end

      Mix.shell().info("""

      #{severity}: #{issue.message}
        File: #{issue.file}:#{issue.line}
        Code: #{issue.code}
      """)
    end)

    error_count = Enum.count(issues, &(&1.severity == :error))
    warning_count = Enum.count(issues, &(&1.severity == :warning))

    Mix.shell().info("""

    Summary: #{error_count} errors, #{warning_count} warnings
    """)
  end

  defp report_json(issues) do
    json = Jason.encode!(issues, pretty: true)
    IO.puts(json)
  end

  defp report_github(issues) do
    # GitHub Actions annotation format
    Enum.each(issues, fn issue ->
      level =
        case issue.severity do
          :error -> "error"
          :warning -> "warning"
        end

      IO.puts("::#{level} file=#{issue.file},line=#{issue.line}::#{issue.message}")
    end)
  end
end
