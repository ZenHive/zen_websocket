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
    * `--fix` - Retained for compatibility; no automatic rewrites are performed
    * `--format` - Output format: `human` (default), `json`, or `github`
    
  ## Examples

      # Validate all Elixir files
      mix zen_websocket.validate_usage
      
      # Validate specific file
      mix zen_websocket.validate_usage lib/my_websocket.ex
      
      # Strict validation with GitHub Actions format
      mix zen_websocket.validate_usage --strict --format github
      
      # --fix is a no-op; it never rewrites files
      mix zen_websocket.validate_usage --fix
  """

  use Mix.Task

  # Lowercase + "(" or "/" is a call/arity/capture; uppercase is a nested module.
  @api_call_pattern ~r/ZenWebsocket\.Client\.([a-z]\w*)(?=[\/(])/

  @allowed_functions ~w(
    connect send_message subscribe get_state close
    get_heartbeat_health get_state_metrics get_latency_stats
    reconnect build_client_struct child_spec start_link t
  )a
  @allowed_function_strings Enum.map(@allowed_functions, &Atom.to_string/1)

  @doc false
  @spec allowed_functions() :: [atom()]
  def allowed_functions, do: @allowed_functions

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
        api_issues = validate_api_usage(file, content, lines)

        antipattern_issues ++ api_issues

      {:error, _} ->
        []
    end
  end

  defp find_antipatterns(file, content, lines) do
    lines_tuple = List.to_tuple(lines)

    Enum.flat_map(common_antipatterns(), fn {pattern, message} ->
      case Regex.run(pattern, content, return: :index) do
        nil ->
          []

        [{start_idx, _length} | _] ->
          line_num = get_line_number(content, start_idx)
          line_content = line_at(lines_tuple, line_num)
          [diagnostic(:antipattern, :warning, file, line_num, message, line_content)]
      end
    end)
  end

  @doc false
  @spec validate_api_usage(String.t(), String.t(), [String.t()]) :: [map()]
  def validate_api_usage(file, content, lines) do
    lines_tuple = List.to_tuple(lines)
    names = Regex.scan(@api_call_pattern, content)
    indexes = Regex.scan(@api_call_pattern, content, return: :index)

    names
    |> Enum.zip(indexes)
    |> Enum.map(&issue_for_match(&1, file, content, lines_tuple))
    |> Enum.reject(&is_nil/1)
  end

  defp issue_for_match({[_full, function], [{start_idx, _} | _]}, file, content, lines_tuple) do
    if function in @allowed_function_strings do
      nil
    else
      line_num = get_line_number(content, start_idx)
      line_content = line_at(lines_tuple, line_num)
      message = "Unknown function Client.#{function}/N - allowed: #{inspect(@allowed_functions)}"
      diagnostic(:invalid_api, :error, file, line_num, message, line_content)
    end
  end

  @spec line_at(tuple(), pos_integer()) :: String.t()
  defp line_at(lines_tuple, line_num) when line_num >= 1 and line_num <= tuple_size(lines_tuple) do
    elem(lines_tuple, line_num - 1)
  end

  defp line_at(_lines_tuple, _line_num), do: ""

  @spec diagnostic(atom(), atom(), String.t(), pos_integer(), String.t(), String.t()) :: %{
          file: String.t(),
          line: pos_integer(),
          type: atom(),
          message: String.t(),
          code: String.t(),
          severity: atom()
        }
  defp diagnostic(type, severity, file, line, message, code) do
    %{
      file: file,
      line: line,
      type: type,
      message: message,
      code: String.trim(code),
      severity: severity
    }
  end

  defp get_line_number(content, char_index) do
    content
    |> String.slice(0, char_index)
    |> String.split("\n")
    |> length()
  end

  defp fix_issues(_issues) do
    Mix.shell().info("No automatic fixes available")
  end

  defp report_issues([], "json"), do: IO.puts("[]")
  defp report_issues([], "github"), do: :ok

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
