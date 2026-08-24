defmodule Mix.Tasks.ZenWebsocket.Usage do
  @shortdoc "Export ZenWebsocket usage rules for AI agents"

  @moduledoc """
  Mix task to export ZenWebsocket usage rules for AI agents and developers.

  This task integrates with the usage_rules library to make ZenWebsocket's
  usage patterns easily accessible in other projects.

  ## Usage

      mix zen_websocket.usage

  ## Options

    * `--format` - Output format: `markdown` (default) or `json`
    * `--output` - Output file path (defaults to stdout)
    * `--sections` - Comma-separated list of sections to include

  ## Examples

      # Output to stdout
      mix zen_websocket.usage

      # Save to file
      mix zen_websocket.usage --output my_rules.md

      # Export specific sections
      mix zen_websocket.usage --sections "quick_start_pattern,common_patterns,error_handling"

      # Export as JSON for programmatic use
      mix zen_websocket.usage --format json --output rules.json
  """

  use Mix.Task

  @usage_rules_path "USAGE_RULES.md"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          format: :string,
          output: :string,
          sections: :string
        ]
      )

    format = Keyword.get(opts, :format, "markdown")
    output = Keyword.get(opts, :output)
    sections = parse_sections(opts[:sections], read_usage_rules())

    case format do
      "markdown" -> export_markdown(output, sections)
      "json" -> export_json(output, sections)
      _ -> Mix.raise("Unknown format: #{format}. Use 'markdown' or 'json'.")
    end
  end

  defp export_markdown(output, sections) do
    content = read_usage_rules()
    filtered = filter_sections(content, sections)

    write_output(filtered, output)
    Mix.shell().info("✅ ZenWebsocket usage rules exported successfully")
  end

  defp export_json(output, sections) do
    content = read_usage_rules()
    filtered = filter_sections(content, sections)

    # Get version from mix.exs project config
    version = :zen_websocket |> Application.spec(:vsn) |> to_string()

    # Simple JSON structure with the markdown content
    json_data = %{
      "format" => "markdown",
      "source" => "ZenWebsocket",
      "version" => version,
      "sections" => sections || "all",
      "content" => filtered
    }

    json = Jason.encode!(json_data, pretty: true)
    write_output(json, output)
    Mix.shell().info("✅ ZenWebsocket usage rules exported as JSON")
  end

  defp read_usage_rules do
    path = Path.join([File.cwd!(), @usage_rules_path])

    case File.read(path) do
      {:ok, content} ->
        content

      {:error, :enoent} ->
        Mix.raise("USAGE_RULES.md not found. Please ensure it exists in the project root.")

      {:error, reason} ->
        Mix.raise("Failed to read USAGE_RULES.md: #{inspect(reason)}")
    end
  end

  defp filter_sections(content, nil), do: content

  defp filter_sections(content, sections) do
    lines = String.split(content, "\n")

    filtered =
      lines
      |> Enum.reduce({[], nil, false}, fn line, {acc, current_section, include} ->
        cond do
          String.starts_with?(line, "## ") ->
            section = normalize_section(line)
            include = section in sections
            {maybe_add_line(acc, line, include), section, include}

          String.starts_with?(line, "# ") ->
            # Always include main title
            {[line | acc], current_section, include}

          true ->
            {maybe_add_line(acc, line, include), current_section, include}
        end
      end)
      |> elem(0)
      |> Enum.reverse()
      |> Enum.join("\n")

    filtered
  end

  defp maybe_add_line(acc, line, true), do: [line | acc]
  defp maybe_add_line(acc, _line, false), do: acc

  defp normalize_section(line) do
    line
    |> String.replace("## ", "")
    |> String.downcase()
    |> String.replace(" ", "_")
    |> String.replace("-", "_")
  end

  defp write_output(content, nil) do
    IO.puts(content)
  end

  defp write_output(content, path) do
    case File.write(path, content) do
      :ok -> Mix.shell().info("Output written to: #{path}")
      {:error, reason} -> Mix.raise("Failed to write output: #{inspect(reason)}")
    end
  end

  defp parse_sections(nil, _content), do: nil

  defp parse_sections(sections_str, content) do
    available = available_sections(content)

    requested =
      sections_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.downcase/1)
      |> Enum.map(&String.replace(&1, "-", "_"))

    case Enum.reject(requested, &(&1 in available)) do
      [] -> requested
      unknown -> Mix.raise(unknown_sections_message(unknown, available))
    end
  end

  # Derived from the document rather than hand-maintained, so a renamed or added
  # `## ` heading can never drift out of sync with the selectable section names.
  defp available_sections(content) do
    content
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "## "))
    |> Enum.map(&normalize_section/1)
  end

  defp unknown_sections_message(unknown, available) do
    IO.iodata_to_binary([
      "Unknown section(s): ",
      Enum.join(unknown, ", "),
      "\n\nAvailable sections:\n  ",
      Enum.join(available, "\n  ")
    ])
  end
end
