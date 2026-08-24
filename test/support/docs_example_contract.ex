defmodule ZenWebsocket.Test.Support.DocsExampleContract do
  @moduledoc """
  Checks Elixir examples in shipped docs against the public API.

  See `ZenWebsocket.DocsExamplesTest` for the checkable-vs-illustrative rule.
  """

  @elixir_langs MapSet.new(["elixir", "iex"])
  @illustrative "illustrative"
  @connect_funs MapSet.new([:connect, :start_link, :child_spec])
  # CommonMark allows a fence to be indented 0–3 spaces (list items).
  @fence ~r/^ {0,3}```(.*)$/
  @skip_funs MapSet.new([
               :alias,
               :case,
               :cond,
               :def,
               :defp,
               :defmodule,
               :defstruct,
               :fn,
               :for,
               :if,
               :import,
               :quote,
               :raise,
               :receive,
               :require,
               :super,
               :throw,
               :try,
               :unless,
               :unquote,
               :use,
               :with
             ])

  @type violation :: %{file: String.t(), line: pos_integer(), symbol: term(), message: String.t()}
  @type block :: %{file: String.t(), line: pos_integer(), code: String.t(), illustrative?: boolean()}

  @spec shipped_files() :: [String.t()]
  def shipped_files do
    markdown = ["README.md", "USAGE_RULES.md"] ++ Path.wildcard("docs/**/*.md")
    Enum.sort(markdown ++ Path.wildcard("lib/**/*.ex"))
  end

  @spec violations() :: [violation()]
  def violations do
    Enum.flat_map(shipped_files(), fn path ->
      check(path, File.read!(path))
    end)
  end

  @spec check(String.t(), String.t()) :: [violation()]
  def check(path, source) do
    path
    |> blocks(source)
    |> Enum.reject(& &1.illustrative?)
    |> Enum.flat_map(&block_violations/1)
  end

  @spec blocks(String.t(), String.t()) :: [block()]
  def blocks(path, source) do
    if String.ends_with?(path, ".ex") do
      moduledoc_blocks(path, source)
    else
      fence_blocks(path, source)
    end
  end

  defp fence_blocks(path, source) do
    source
    |> numbered_fences()
    |> Enum.filter(&elixir_fence?/1)
    |> Enum.map(fn {line, info, code} ->
      %{file: path, line: line, code: code, illustrative?: illustrative?(info, code), fenced?: true}
    end)
  end

  defp numbered_fences(source) do
    lines = String.split(source, "\n")

    lines
    |> Enum.reduce({1, :idle, []}, fn raw, {n, state, acc} ->
      fence_line(raw, n, state, acc)
    end)
    |> elem(2)
    |> Enum.reverse()
  end

  defp fence_line(raw, n, :idle, acc) do
    case fence_info(raw) do
      {:ok, info} -> {n + 1, {:fence, n, info, []}, acc}
      :none -> {n + 1, :idle, acc}
    end
  end

  defp fence_line(raw, n, {:fence, start, info, buf}, acc) do
    case fence_info(raw) do
      {:ok, _} ->
        code = buf |> Enum.reverse() |> Enum.join("\n")
        {n + 1, :idle, [{start, info, code} | acc]}

      :none ->
        {n + 1, {:fence, start, info, [raw | buf]}, acc}
    end
  end

  defp fence_info(raw) do
    case Regex.run(@fence, raw) do
      [_, info] -> {:ok, String.trim(info)}
      nil -> :none
    end
  end

  defp elixir_fence?({_line, info, _code}) do
    case fence_tokens(info) do
      [lang | _] -> MapSet.member?(@elixir_langs, String.downcase(lang))
      [] -> false
    end
  end

  defp fence_tokens(info), do: String.split(info, ~r/[\s,]+/, trim: true)

  defp illustrative?(info, code) do
    @illustrative in fence_tokens(info) or illustrative_comment?(code)
  end

  defp illustrative_comment?(code) do
    code
    |> String.split("\n")
    |> Enum.find(&(String.trim(&1) != ""))
    |> case do
      nil -> false
      line -> String.match?(String.trim(line), ~r/^#\s*illustrative\b/)
    end
  end

  defp moduledoc_blocks(path, source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        ast
        |> collect_moduledocs([])
        |> Enum.flat_map(fn {attr_line, doc} ->
          doc
          |> numbered_fences()
          |> Enum.filter(&elixir_fence?/1)
          |> Enum.map(fn {line, info, code} ->
            %{
              file: path,
              line: attr_line + line,
              code: code,
              illustrative?: illustrative?(info, code),
              fenced?: true
            }
          end)
          |> Kernel.++(indented_elixir_blocks(path, attr_line, doc))
        end)

      {:error, _} ->
        []
    end
  end

  defp collect_moduledocs(ast, acc) do
    {_, docs} =
      Macro.prewalk(ast, acc, fn
        {:@, meta, [{:moduledoc, _, [doc]}]} = node, docs when is_binary(doc) ->
          {node, [{meta[:line] || 1, doc} | docs]}

        node, docs ->
          {node, docs}
      end)

    Enum.reverse(docs)
  end

  defp indented_elixir_blocks(path, attr_line, doc) do
    doc
    |> String.split("\n")
    |> indented_runs()
    |> Enum.map(fn {line, code} ->
      %{
        file: path,
        line: attr_line + line,
        code: dedent(code),
        illustrative?: illustrative_comment?(code),
        fenced?: false
      }
    end)
  end

  defp indented_runs(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce({:idle, []}, &indent_step/2)
    |> finish_indent()
  end

  defp indent_step({line, n}, {:idle, acc}) do
    if indented_code_line?(line), do: {{:run, n, [line]}, acc}, else: {:idle, acc}
  end

  defp indent_step({line, _n}, {{:run, start, buf}, acc}) do
    if indented_code_line?(line) or String.trim(line) == "" do
      {{:run, start, [line | buf]}, acc}
    else
      {:idle, [{start, flush_indent(buf)} | acc]}
    end
  end

  defp finish_indent({:idle, acc}), do: Enum.reverse(acc)
  defp finish_indent({{:run, start, buf}, acc}), do: Enum.reverse([{start, flush_indent(buf)} | acc])

  defp flush_indent(buf), do: buf |> Enum.reverse() |> Enum.join("\n") |> String.trim_trailing()

  defp indented_code_line?(line) do
    String.starts_with?(line, "    ") and String.trim(line) != "" and
      not String.match?(line, ~r/^\s{0,3}[-*+]|\s{0,3}\d+\.\s/)
  end

  defp dedent(code) do
    code
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "    " <> rest -> rest
      line -> String.replace_prefix(line, "    ", "")
    end)
  end

  defp block_violations(%{code: code, fenced?: fenced?} = block) do
    case quoted(code) do
      {:ok, ast} -> ast_violations(block, ast)
      {:error, _reason} when not fenced? -> []
      {:error, reason} -> [violation(block, :unparseable, "checkable block did not parse: #{reason}")]
    end
  end

  defp quoted(code) do
    stripped = strip_iex(code)

    case Code.string_to_quoted(stripped) do
      {:ok, ast} -> {:ok, ast}
      {:error, _} -> wrap_module(stripped)
    end
  end

  defp wrap_module(code) do
    case Code.string_to_quoted("defmodule DocExampleSnippet do\n#{code}\nend\n") do
      {:ok, ast} -> {:ok, ast}
      {:error, {meta, desc, token}} -> {:error, "#{desc}#{token} (line #{meta[:line] || "?"})"}
    end
  end

  defp strip_iex(code) do
    code
    |> String.replace(~r/^iex(?: \(\d+\))?> /m, "")
    |> String.replace(~r/^\.\.\.> /m, "")
  end

  defp ast_violations(block, ast) do
    aliases = collect_aliases(ast)
    bindings = collect_bindings(ast)
    {_, calls} = Macro.prewalk(ast, [], &collect_call(&1, &2, aliases, bindings))
    Enum.flat_map(Enum.reverse(calls), &call_violations(block, &1))
  end

  defp collect_aliases(ast) do
    {_, aliases} = Macro.prewalk(ast, %{}, &alias_step/2)
    aliases
  end

  defp alias_step({:alias, _, [{{:., _, [{:__aliases__, _, prefix}, :{}]}, _, names}]}, acc) do
    {:ok, Enum.reduce(names, acc, &put_curly_alias(&1, prefix, &2))}
  end

  defp alias_step({:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, as_parts}]]}, acc) do
    {:ok, Map.put(acc, List.last(as_parts), Module.concat(parts))}
  end

  defp alias_step({:alias, _, [{:__aliases__, _, parts}]}, acc) do
    {:ok, Map.put(acc, List.last(parts), Module.concat(parts))}
  end

  defp alias_step(node, acc), do: {node, acc}

  defp put_curly_alias({:__aliases__, _, name_parts}, prefix, acc) do
    Map.put(acc, List.last(name_parts), Module.concat(prefix ++ name_parts))
  end

  defp collect_bindings(ast) do
    {_, bindings} =
      Macro.prewalk(ast, %{}, fn
        {:=, _, [{name, _, ctx}, value]} = node, acc when is_atom(name) and is_atom(ctx) ->
          {node, maybe_put_kw(acc, name, value)}

        node, acc ->
          {node, acc}
      end)

    bindings
  end

  defp maybe_put_kw(acc, name, value) do
    if keyword_literal?(value), do: Map.put(acc, name, keyword_keys(value)), else: acc
  end

  defp collect_call({:|>, meta, [left, {{:., _, [mod, fun]}, call_meta, args}]}, acc, aliases, bindings)
       when is_atom(fun) and is_list(args) do
    acc = [{:call, resolve_mod(mod, aliases), fun, length(args) + 1, option_keys(args, bindings)} | acc]
    {{:|>, meta, [left, {:__piped__, call_meta, args}]}, acc}
  end

  defp collect_call({:&, _, [{:/, _, [{{:., _, [mod, fun]}, _, []}, arity]}]}, acc, aliases, _bindings)
       when is_atom(fun) and is_integer(arity) do
    {:ok, [{:capture, resolve_mod(mod, aliases), fun, arity} | acc]}
  end

  defp collect_call({{:., _, [mod, fun]}, _, args} = node, acc, aliases, bindings) when is_atom(fun) and is_list(args) do
    {node, [{:call, resolve_mod(mod, aliases), fun, length(args), option_keys(args, bindings)} | acc]}
  end

  defp collect_call({{:__aliases__, _, _} = mod, opts} = node, acc, aliases, _bindings) do
    if keyword_literal?(opts) do
      {node, [{:call, resolve_mod(mod, aliases), :child_spec, 1, keyword_keys(opts)} | acc]}
    else
      {node, acc}
    end
  end

  defp collect_call(node, acc, _aliases, _bindings), do: {node, acc}

  defp option_keys(args, bindings) do
    case List.last(args) do
      {name, _, ctx} when is_atom(name) and is_atom(ctx) -> Map.get(bindings, name, [])
      opts -> if keyword_literal?(opts), do: keyword_keys(opts), else: []
    end
  end

  defp keyword_literal?(ast) when is_list(ast) do
    ast != [] and
      Enum.all?(ast, fn
        {key, _value} when is_atom(key) -> true
        _other -> false
      end)
  end

  defp keyword_literal?(_ast), do: false

  defp keyword_keys(ast), do: Enum.map(ast, &elem(&1, 0))

  defp resolve_mod({:__aliases__, _, parts}, aliases) do
    case parts do
      [first | rest] ->
        case Map.get(aliases, first) do
          nil -> Module.concat(parts)
          prefix when rest == [] -> prefix
          prefix -> Module.concat([prefix | rest])
        end

      _ ->
        nil
    end
  end

  defp resolve_mod(mod, _aliases) when is_atom(mod), do: mod
  defp resolve_mod(_mod, _aliases), do: nil

  defp call_violations(block, {:capture, mod, fun, arity}), do: call_violations(block, {:call, mod, fun, arity, []})
  defp call_violations(_block, {_kind, nil, _fun, _arity, _keys}), do: []

  defp call_violations(block, {_kind, mod, fun, arity, keys}) when is_atom(fun) do
    cond do
      MapSet.member?(@skip_funs, fun) ->
        []

      skip_module?(mod) ->
        []

      true ->
        case load_module(mod) do
          {:ok, loaded} -> function_and_option_violations(block, loaded, fun, arity, keys)
          :skip -> []
        end
    end
  end

  defp skip_module?(Kernel), do: true
  defp skip_module?(Access), do: true
  defp skip_module?(_mod), do: false

  defp load_module(mod) when not is_atom(mod), do: :skip

  defp load_module(mod) do
    cond do
      app_module?(mod) -> {:ok, mod}
      zen = zen_submodule(mod) -> {:ok, zen}
      suffix = unique_zen_suffix(mod) -> {:ok, suffix}
      match?({:module, _}, Code.ensure_loaded(mod)) -> {:ok, mod}
      true -> :skip
    end
  end

  defp app_module?(mod) do
    match?("Elixir.ZenWebsocket" <> _, Atom.to_string(mod)) and match?({:module, _}, Code.ensure_loaded(mod))
  end

  defp zen_submodule(mod) do
    case elixir_last_segment(mod) do
      nil ->
        nil

      last ->
        candidate = Module.concat(ZenWebsocket, last)

        if candidate != mod and match?({:module, _}, Code.ensure_loaded(candidate)) do
          candidate
        end
    end
  end

  defp unique_zen_suffix(mod) do
    last = elixir_last_segment(mod)
    if last, do: unique_suffix_match(last)
  end

  defp elixir_last_segment(mod) when is_atom(mod) do
    case Atom.to_string(mod) do
      "Elixir." <> _ = name -> name |> Module.split() |> List.last()
      _ -> nil
    end
  end

  defp unique_suffix_match(last) do
    matches =
      Enum.filter(zen_modules(), fn candidate ->
        List.last(Module.split(candidate)) == last
      end)

    case matches do
      [only] -> only
      _ -> nil
    end
  end

  defp zen_modules do
    case :application.get_key(:zen_websocket, :modules) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp function_and_option_violations(block, mod, fun, arity, keys) do
    case export_violations(block, mod, fun, arity) do
      [] -> option_violations(block, mod, fun, arity, keys)
      export_vs -> export_vs
    end
  end

  defp export_violations(block, mod, fun, arity) do
    if exported?(mod, fun, arity) do
      []
    else
      symbol = "#{inspect(mod)}.#{fun}/#{arity}"
      [violation(block, symbol, "function does not exist at this arity")]
    end
  end

  defp exported?(mod, fun, arity) do
    match?({:module, _}, Code.ensure_loaded(mod)) and
      (function_exported?(mod, fun, arity) or macro_exported?(mod, fun, arity))
  end

  defp option_violations(block, mod, fun, arity, keys) do
    accepted = accepted_keys(mod, fun)

    unknown =
      if accepted == [] do
        []
      else
        for key <- keys, key not in accepted do
          violation(block, key, "option is never read by #{inspect(mod)}.#{fun}/#{arity}")
        end
      end

    unknown ++ special_option_violations(block, mod, fun, keys)
  end

  defp special_option_violations(block, mod, fun, keys) do
    heartbeat_vs(block, mod, fun, keys) ++ handler_vs(block, mod, fun, keys)
  end

  defp heartbeat_vs(block, ZenWebsocket.Client, fun, keys) do
    if MapSet.member?(@connect_funs, fun) and :heartbeat_interval in keys and :heartbeat_config not in keys do
      [
        violation(
          block,
          :heartbeat_interval,
          "Client.#{fun} starts no timer unless :heartbeat_config is also set"
        )
      ]
    else
      []
    end
  end

  defp heartbeat_vs(block, ZenWebsocket.ClientSupervisor, :start_client, keys) do
    heartbeat_vs(block, ZenWebsocket.Client, :connect, keys)
  end

  defp heartbeat_vs(_block, _mod, _fun, _keys), do: []

  defp handler_vs(block, ZenWebsocket.ClientSupervisor, :start_client, keys) do
    missing_handler(block, keys, "ClientSupervisor.start_client/2 requires :handler or frames are discarded")
  end

  defp handler_vs(block, ZenWebsocket.Client, fun, keys) when fun in [:start_link, :child_spec] do
    missing_handler(block, keys, "Client.#{fun} requires :handler or frames are discarded")
  end

  defp handler_vs(_block, _mod, _fun, _keys), do: []

  defp missing_handler(block, keys, message) do
    if :handler in keys do
      []
    else
      [violation(block, :handler, message)]
    end
  end

  defp accepted_keys(ZenWebsocket.Client, fun) when fun in [:connect, :start_link, :child_spec] do
    connect_keys()
  end

  defp accepted_keys(ZenWebsocket.ClientSupervisor, :start_client), do: connect_keys() ++ [:timeout]
  defp accepted_keys(ZenWebsocket.Config, fun) when fun in [:new, :new!], do: config_fields()
  defp accepted_keys(ZenWebsocket.ClientSupervisor, :send_balanced), do: [:max_attempts, :client_discovery]
  defp accepted_keys(ZenWebsocket.Testing, :start_mock_server), do: [:port, :protocol, :handler]
  defp accepted_keys(ZenWebsocket.Recorder, :replay), do: [:realtime]
  defp accepted_keys(_mod, _fun), do: []

  defp connect_keys do
    config_fields() ++ [:handler, :heartbeat_config, :on_connect, :on_disconnect, :reconnector, :id]
  end

  defp config_fields do
    ZenWebsocket.Config.__struct__()
    |> Map.from_struct()
    |> Map.keys()
  end

  defp violation(block, symbol, message) do
    %{file: block.file, line: block.line, symbol: symbol, message: message}
  end
end
