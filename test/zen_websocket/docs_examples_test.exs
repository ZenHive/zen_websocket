defmodule ZenWebsocket.DocsExamplesTest do
  @moduledoc """
  Encodes the doc-example contract: a checkable Elixir fence may only name
  functions and options the shipped library actually has.

  ## Checkable vs illustrative

  Every fenced `elixir` or `iex` block in README.md, USAGE_RULES.md, `docs/**`,
  and every `@moduledoc` under `lib/` is **checkable** unless the source
  document opts it out. Fences indented 0–3 spaces (CommonMark list items)
  are included.

  Opt out by putting the token `illustrative` on the fence (`elixir illustrative`)
  or as the first comment of the block (`# illustrative`). That marker lives in
  the document a reader edits, not in a skip list in this test.

  Checkable blocks are copy-paste calls. Illustrative blocks are partial
  fragments that invent a module the reader is expected to supply
  (`YourExchange.Adapter`, `MyApp.Consumer`, …).

  ## What is checked

  Remote calls whose module is this library, Elixir/OTP, or a Mix dependency
  must exist at the stated arity. Keyword options passed to `Client.connect/2`,
  `Client.start_link/2`, `Client.child_spec/1`, `ClientSupervisor.start_client/2`,
  `Config.new/2`, and the other catalogued receivers must be keys that function
  reads. `:heartbeat_interval` on a Client connect-family call requires
  `:heartbeat_config` (interval alone starts no timer). Supervised
  `start_client` / `start_link` / `child_spec` examples must pass `:handler`.

  Calls to modules that cannot be loaded (the reader's `MyApp.*`) are ignored.
  """

  use ExUnit.Case, async: true

  alias ZenWebsocket.Test.Support.DocsExampleContract

  @fixture "test/fixtures/docs_example_contract/heartbeat_interval_only.md"

  test "every checkable shipped example names a real function and readable options" do
    assert DocsExampleContract.violations() == []
  end

  test "reintroducing heartbeat_interval-only names the file, block line, and symbol" do
    source = File.read!(@fixture)
    [violation] = DocsExampleContract.check(@fixture, source)

    assert violation.file == @fixture
    assert violation.line == 5
    assert violation.symbol == :heartbeat_interval
    assert violation.message =~ "heartbeat_config"
  end

  test "indented elixir fences are checked and name the missing function" do
    source = """
    1. Check Gun
       ```elixir
       IO.inspect(length(:gun.info()))
       ```
    """

    [violation] = DocsExampleContract.check("list.md", source)
    assert violation.file == "list.md"
    assert violation.line == 2
    assert violation.symbol == ":gun.info/0"
  end

  test "unknown function names the file, block line, and symbol" do
    source = """
    ```elixir
    ZenWebsocket.Config.not_a_real_function()
    ```
    """

    [violation] = DocsExampleContract.check("missing.md", source)
    assert violation.file == "missing.md"
    assert violation.line == 1
    assert violation.symbol == "ZenWebsocket.Config.not_a_real_function/0"
  end

  test "unknown option names the file, block line, and symbol" do
    source = """
    ```elixir
    ZenWebsocket.Client.connect("wss://example.com", not_a_real_opt: true)
    ```
    """

    [violation] = DocsExampleContract.check("opts.md", source)
    assert violation.file == "opts.md"
    assert violation.line == 1
    assert violation.symbol == :not_a_real_opt
  end

  test "start_client without handler names the missing option" do
    source = """
    ```elixir
    ZenWebsocket.ClientSupervisor.start_client("wss://example.com")
    ```
    """

    [violation] = DocsExampleContract.check("handler.md", source)
    assert violation.file == "handler.md"
    assert violation.line == 1
    assert violation.symbol == :handler
  end

  test "illustrative fence token opts a partial block out" do
    source = """
    ```elixir illustrative
    ZenWebsocket.Config.not_a_real_function()
    ```
    """

    assert DocsExampleContract.check("skip.md", source) == []
  end

  test "start_link without handler names the missing option" do
    source = """
    ```elixir
    ZenWebsocket.Client.start_link("wss://example.com")
    ```
    """

    [violation] = DocsExampleContract.check("start_link.md", source)
    assert violation.file == "start_link.md"
    assert violation.line == 1
    assert violation.symbol == :handler
  end

  test "child_spec tuple without handler names the missing option" do
    source = """
    ```elixir
    {ZenWebsocket.Client, url: "wss://example.com", id: :ws}
    ```
    """

    [violation] = DocsExampleContract.check("child_spec.md", source)
    assert violation.file == "child_spec.md"
    assert violation.line == 1
    assert violation.symbol == :handler
  end

  test "illustrative first-comment opts a partial block out" do
    source = """
    ```elixir
    # illustrative
    ZenWebsocket.Config.not_a_real_function()
    ```
    """

    assert DocsExampleContract.check("skip-comment.md", source) == []
  end
end
