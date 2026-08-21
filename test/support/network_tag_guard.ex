defmodule ZenWebsocket.Test.Support.NetworkTagGuard do
  @moduledoc """
  Checks that each ExUnit test's network tags match the sockets it opens.

  The guard follows module, describe, and test tag scope. It rejects internet
  URLs without `:external_network`, mock servers without `:local_network`,
  network tags without `:integration`, and mock-backed tests selected by
  `--only external_network`.
  """

  alias ZenWebsocket.Test.Support.NetworkTagGuard.Ast
  alias ZenWebsocket.Test.Support.NetworkTagGuard.Scope

  @test_glob "**/*_test.exs"

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
      {:ok, ast} -> Enum.flat_map(Ast.modules(ast), &module_violations(&1, path))
      {:error, {_line, error, token}} -> ["#{path}: cannot parse (#{error}#{token})"]
    end
  end

  defp file_violations(path) do
    Enum.map(check_source(path, File.read!(path)), &{path, &1})
  end

  defp module_violations({:defmodule, _, [alias_ast, [do: body]]}, _path) do
    statements = Ast.block(body)
    Scope.violations(Macro.to_string(alias_ast), statements, Ast.context(statements))
  end
end

defmodule ZenWebsocket.Test.Support.NetworkTagGuard.Ast do
  @moduledoc false

  @type context :: %{attrs: %{atom() => term()}, callbacks: %{atom() => Macro.t()}}

  @spec block(Macro.t()) :: [Macro.t()]
  def block({:__block__, _, statements}), do: statements
  def block(statement), do: [statement]

  @spec modules(Macro.t()) :: [Macro.t()]
  def modules({:defmodule, _, _} = ast), do: [ast]
  def modules({:__block__, _, statements}), do: Enum.flat_map(statements, &modules/1)
  def modules(_ast), do: []

  @spec tag_names(list()) :: [atom()]
  def tag_names([tag]) when is_atom(tag), do: [tag]
  def tag_names([{:__block__, _, [tag]}]) when is_atom(tag), do: [tag]
  def tag_names([keyword]) when is_list(keyword), do: Keyword.keys(keyword)
  def tag_names(_args), do: []

  @spec context([Macro.t()]) :: context()
  def context(statements) do
    Enum.reduce(statements, %{attrs: %{}, callbacks: %{}}, fn
      {:@, _, [{name, _, [value]}]}, context when is_atom(name) ->
        put_in(context, [:attrs, name], value)

      {kind, _, [{name, _, _args}, [do: body]]}, context when kind in [:def, :defp] ->
        put_in(context, [:callbacks, name], body)

      _statement, context ->
        context
    end)
  end
end

defmodule ZenWebsocket.Test.Support.NetworkTagGuard.Resources do
  @moduledoc false

  alias ZenWebsocket.Test.Support.NetworkTagGuard.Ast

  @external :external_network
  @internet_reference :internet_reference
  @local :local_network
  @socket_functions [:connect, :start_client, :start_connection, :start_link, :start_multiple]
  @socket_reference :socket_reference

  @spec flags(Macro.t(), Ast.context()) :: MapSet.t(atom())
  def flags(ast, context) do
    {_, resources} = Macro.prewalk(ast, MapSet.new(), &classify(&1, &2, context))

    resources =
      if MapSet.member?(resources, @internet_reference) and MapSet.member?(resources, @socket_reference) do
        MapSet.put(resources, @external)
      else
        resources
      end

    MapSet.difference(resources, MapSet.new([@internet_reference, @socket_reference]))
  end

  defp classify(url, resources, _context) when is_binary(url) do
    updated = if external_url?(url), do: MapSet.put(resources, @internet_reference), else: resources
    {url, updated}
  end

  defp classify({:@, _, [{name, _, _}]} = node, resources, context) do
    updated = if external_url?(context.attrs[name]), do: MapSet.put(resources, @internet_reference), else: resources
    {node, updated}
  end

  defp classify({:setup, _, [callback]} = node, resources, context) when is_atom(callback) do
    body = Map.get(context.callbacks, callback)
    callback_resources = if body, do: flags(body, %{context | callbacks: %{}}), else: MapSet.new()
    {node, MapSet.union(resources, callback_resources)}
  end

  defp classify({{:., _, [{:__aliases__, _, parts}, :start_mock_server]}, _, _} = node, resources, _context) do
    {node, if(List.last(parts) == :Testing, do: MapSet.put(resources, @local), else: resources)}
  end

  defp classify({:__aliases__, _, parts} = node, resources, _context) do
    {node, if(List.last(parts) == :MockWebSockServer, do: MapSet.put(resources, @local), else: resources)}
  end

  defp classify({:start_mock_server, _, _} = node, resources, _context) do
    {node, MapSet.put(resources, @local)}
  end

  defp classify({{:., _, [_module, function]}, _, args} = node, resources, context) when function in @socket_functions do
    updated = MapSet.put(resources, @socket_reference)
    updated = if internet_args?(args, context), do: MapSet.put(updated, @external), else: updated
    {node, updated}
  end

  defp classify({function, _, args} = node, resources, context) when function in @socket_functions and is_list(args) do
    updated = MapSet.put(resources, @socket_reference)
    updated = if internet_args?(args, context), do: MapSet.put(updated, @external), else: updated
    {node, updated}
  end

  defp classify(node, resources, _context), do: {node, resources}

  defp internet_args?(args, context) do
    {_, found?} =
      Macro.prewalk(args, false, fn
        url, found? when is_binary(url) -> {url, found? or external_url?(url)}
        {:@, _, [{name, _, _}]} = node, found? -> {node, found? or external_url?(context.attrs[name])}
        node, found? -> {node, found?}
      end)

    found?
  end

  defp external_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["ws", "wss"] ->
        is_binary(host) and host not in ["localhost", "127.0.0.1", "::1", "0.0.0.0"]

      _other ->
        false
    end
  end

  defp external_url?(_value), do: false
end

defmodule ZenWebsocket.Test.Support.NetworkTagGuard.Scope do
  @moduledoc false

  alias ZenWebsocket.Test.Support.NetworkTagGuard.Ast
  alias ZenWebsocket.Test.Support.NetworkTagGuard.Resources

  @network_tags [:external_network, :local_network]
  @test_macros [:property, :test]

  @spec violations(String.t(), [Macro.t()], Ast.context()) :: [String.t()]
  def violations(module_name, statements, context) do
    walk(statements, module_name, context, [], MapSet.new())
  end

  defp walk(statements, module_name, context, inherited_tags, inherited_resources) do
    initial = {inherited_tags, [], inherited_resources, []}

    statements
    |> Enum.reduce(initial, &step(&1, &2, {module_name, context}))
    |> elem(3)
  end

  defp step({:@, _, [{kind, _, args}]}, {tags, pending, resources, violations}, _context)
       when kind in [:describetag, :moduletag] do
    {tags ++ Ast.tag_names(args), pending, resources, violations}
  end

  defp step({:@, _, [{:tag, _, args}]}, {tags, pending, resources, violations}, _context) do
    {tags, pending ++ Ast.tag_names(args), resources, violations}
  end

  defp step({:setup, _, _} = setup, {tags, pending, resources, violations}, {_name, context}) do
    {tags, pending, MapSet.union(resources, Resources.flags(setup, context)), violations}
  end

  defp step({:describe, _, [_label, [do: body]]}, state, {module_name, context}) do
    {tags, pending, resources, violations} = state
    nested = walk(Ast.block(body), module_name, context, tags, resources)
    {tags, pending, resources, violations ++ nested}
  end

  defp step({kind, _, args} = test, state, {module_name, context}) when kind in @test_macros do
    {tags, pending, resources, violations} = state
    effective_tags = Enum.uniq(tags ++ pending)
    effective_resources = MapSet.union(resources, Resources.flags(test, context))
    found = findings(module_name, label(args), effective_tags, effective_resources)
    {tags, [], resources, violations ++ found}
  end

  defp step(_statement, state, _context), do: state

  defp findings(module_name, test_name, tags, resources) do
    prefix = "#{module_name} #{inspect(test_name)}"

    for {true, message} <- [
          {MapSet.member?(resources, :external_network) and :external_network not in tags,
           "#{prefix}: internet URL without :external_network"},
          {MapSet.member?(resources, :local_network) and :local_network not in tags,
           "#{prefix}: MockWebSockServer without :local_network"},
          {Enum.any?(@network_tags, &(&1 in tags)) and :integration not in tags,
           "#{prefix}: network tag without :integration"},
          {MapSet.member?(resources, :local_network) and :external_network in tags,
           "#{prefix}: MockWebSockServer selected by :external_network"}
        ],
        do: message
  end

  defp label([name | _args]) when is_binary(name), do: name
  defp label(_args), do: "unnamed test"
end
