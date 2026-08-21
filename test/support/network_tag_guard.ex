defmodule ZenWebsocket.Test.Support.NetworkTagGuard do
  @moduledoc """
  Static checks that each ExUnit suite's network tags match the sockets it opens.

  A suite (one `defmodule`) fails when it:

  * dials a non-local `ws://` / `wss://` URL without `:external_network`
  * starts `MockWebSockServer` / `Testing.start_mock_server` without `:local_network`
  * carries `:external_network` or `:local_network` without `:integration`
  * starts a mock server in module `setup` while also tagging `:external_network`
    (`mix test --only external_network` would still boot the mock)
  """

  @test_glob "**/*_test.exs"
  @socket_funs [:connect, :start_client, :start_connection, :start_link, :start_multiple]
  @network_tags [:external_network, :local_network]
  @tag_kinds [:tag, :moduletag, :describetag]
  @examples [:test, :property]

  @spec scan(Path.t()) :: [{Path.t(), String.t()}]
  def scan(root) do
    root
    |> Path.join(@test_glob)
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(&file_violations/1)
  end

  @spec check_source(Path.t(), String.t()) :: [String.t()]
  def check_source(path, source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} -> Enum.flat_map(modules(ast), &module_violations(&1, path))
      {:error, {_line, error, token}} -> ["#{path}: cannot parse (#{error}#{token})"]
    end
  end

  defp file_violations(path), do: Enum.map(check_source(path, File.read!(path)), &{path, &1})

  defp modules({:defmodule, _, _} = ast), do: [ast]
  defp modules({:__block__, _, stmts}), do: Enum.flat_map(stmts, &modules/1)
  defp modules(_), do: []

  defp module_violations({:defmodule, _, [alias_ast, [do: body]]}, _path) do
    name = Macro.to_string(alias_ast)
    stmts = block(body)
    attrs = internet_attrs(stmts)
    tags = collect_tags(stmts)
    mod_tags = module_tags(stmts)
    mock? = mock_ref?(body)
    internet? = internet_connect?(body, attrs)
    module_mock_setup? = module_setup_starts_mock?(stmts)

    internet_msg = "#{name}: internet URL without :external_network"
    mock_msg = "#{name}: MockWebSockServer without :local_network"
    setup_msg = "#{name}: module setup starts MockWebSockServer while :external_network is set"

    []
    |> maybe_add(internet? and :external_network not in tags, internet_msg)
    |> maybe_add(mock? and :local_network not in tags, mock_msg)
    |> Enum.concat(pairing_violations(name, mod_tags, [], stmts))
    |> maybe_add(module_mock_setup? and :external_network in tags, setup_msg)
  end

  defp maybe_add(viols, true, msg), do: viols ++ [msg]
  defp maybe_add(viols, false, _msg), do: viols

  defp block({:__block__, _, stmts}), do: stmts
  defp block(stmt), do: [stmt]

  defp internet_attrs(stmts) do
    for {:@, _, [{name, _, [url]}]} <- stmts,
        is_atom(name) and is_binary(url) and internet_url?(url),
        into: MapSet.new(),
        do: name
  end

  defp collect_tags(stmts) do
    {_, tags} =
      Macro.prewalk(stmts, [], fn
        {:@, _, [{kind, _, args}]} = node, acc when kind in @tag_kinds ->
          {node, tag_names(args) ++ acc}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(tags)
  end

  defp tag_names([tag]) when is_atom(tag), do: [tag]
  defp tag_names([{:__block__, _, [tag]}]) when is_atom(tag), do: [tag]
  defp tag_names([kw]) when is_list(kw), do: Keyword.keys(kw)
  defp tag_names(_), do: []

  defp module_tags(stmts) do
    Enum.flat_map(stmts, fn
      {:@, _, [{:moduletag, _, args}]} -> tag_names(args)
      _ -> []
    end)
  end

  defp example_tags({:@, _, [{:tag, _, args}]}), do: tag_names(args)
  defp example_tags(_), do: []

  defp mock_ref?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _, parts} = node, acc ->
          {node, acc or List.last(parts) == :MockWebSockServer}

        {{:., _, [{:__aliases__, _, parts}, :start_mock_server]}, _, _} = node, acc ->
          {node, acc or List.last(parts) == :Testing}

        :start_mock_server, _acc ->
          {:start_mock_server, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp module_setup_starts_mock?(stmts) do
    Enum.any?(stmts, fn
      {:setup, _, args} -> mock_ref?(args)
      _ -> false
    end)
  end

  defp internet_connect?(ast, attrs) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [_, fun]}, _, args} = node, acc when fun in @socket_funs ->
          {node, acc or internet_args?(args, attrs)}

        {fun, _, args} = node, acc when fun in @socket_funs and is_list(args) ->
          {node, acc or internet_args?(args, attrs)}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp internet_args?(args, attrs) do
    {_, found} =
      Macro.prewalk(args, false, fn
        bin, acc when is_binary(bin) -> {bin, acc or internet_url?(bin)}
        {:@, _, [{name, _, _}]} = node, acc -> {node, acc or MapSet.member?(attrs, name)}
        node, acc -> {node, acc}
      end)

    found
  end

  defp internet_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["ws", "wss"] ->
        is_binary(host) and host not in ["localhost", "127.0.0.1", "::1"]

      _ ->
        false
    end
  end

  defp pairing_violations(name, mod_tags, desc_tags, stmts) do
    {_, viols} =
      Enum.reduce(stmts, {[], []}, fn stmt, {pending, viols} ->
        pair_stmt(name, mod_tags, desc_tags, stmt, pending, viols)
      end)

    viols
  end

  defp pair_stmt(name, mod_tags, desc_tags, {:describe, _, [_, [do: body]]}, pending, viols) do
    inner = block(body)
    nested = pairing_violations(name, mod_tags, desc_tags ++ describe_tags(inner), inner)
    {pending, viols ++ nested}
  end

  defp pair_stmt(name, mod_tags, desc_tags, {kind, _, _}, pending, viols) when kind in @examples do
    {[], viols ++ missing_integration(name, mod_tags ++ desc_tags ++ pending)}
  end

  defp pair_stmt(_name, _mod_tags, _desc_tags, stmt, pending, viols) do
    {pending ++ example_tags(stmt), viols}
  end

  defp describe_tags(stmts) do
    Enum.flat_map(stmts, fn
      {:@, _, [{:describetag, _, args}]} -> tag_names(args)
      {:@, _, [{:moduletag, _, args}]} -> tag_names(args)
      _ -> []
    end)
  end

  defp missing_integration(name, tags) do
    if Enum.any?(@network_tags, &(&1 in tags)) and :integration not in tags do
      ["#{name}: network tag without :integration"]
    else
      []
    end
  end
end
