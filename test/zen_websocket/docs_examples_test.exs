defmodule ZenWebsocket.DocsExamplesTest do
  @moduledoc """
  Encodes the doc-example contract: a checkable Elixir fence may only name
  functions and options the shipped library actually has.

  ## Checkable vs illustrative

  Every fenced `elixir` or `iex` block in README.md, USAGE_RULES.md, `docs/**`,
  and every `@moduledoc` under `lib/` is **checkable** unless the source
  document opts it out.

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
  `start_client` examples must pass `:handler`.

  Calls to modules that are not loaded (the reader's `MyApp.*`) are ignored.
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
end
