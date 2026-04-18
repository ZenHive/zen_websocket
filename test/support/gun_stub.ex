defmodule ZenWebsocket.Test.Support.GunStub do
  @moduledoc """
  Shape-only constructors for the four Gun transport message tuples.

  Scope is fenced per the R044 testing-policy amendment: this helper exists
  *solely* to build the opaque transport shapes consumed by
  `ZenWebsocket.MessageHandler.handle_message/2`. Shape-only fixtures are
  permitted because Gun's `pid()` and `stream_ref()` are opaque BEAM
  primitives with no public behavior for a fixture to drift against.

  ## API shape

  All four constructors take a keyword list. Every field has a sensible
  default (real `self()` pid, real `make_ref/0` ref), so tests can specify
  only the fields they care about. Unknown keys raise via
  `Keyword.validate!/2`, catching typos at call time.

      GunStub.gun_upgrade()                              # all defaults
      GunStub.gun_ws(frame: {:text, "hi"})
      GunStub.gun_down(reason: :timeout)
      GunStub.gun_down(reason: r, conn_pid: pid)         # explicit pid
      GunStub.gun_error(reason: :badarg, stream_ref: sr)

  ## Permitted

  Constructing the four Gun tuple shapes with **real** pids (from `self/0`
  or `spawn/1`) and **real** refs (from `make_ref/0`).

      {:gun_upgrade, conn_pid, stream_ref, ["websocket"], headers}
      {:gun_ws, conn_pid, stream_ref, frame}
      {:gun_down, conn_pid, protocol, reason, killed_streams}
      {:gun_error, conn_pid, stream_ref, reason}

  ## NOT Permitted

  This helper must never grow to cover:

    * API response fixtures (Deribit, Binance, any exchange)
    * Authentication flow simulation
    * Exchange behavior (subscription acks, order responses, heartbeats)
    * Any fixture with semantic content beyond the raw transport-frame shape

  `ZenWebsocket.Test.Support.MockWebSockServer` (real cowboy/websock stack)
  and real-API tests remain the source of truth for all business logic.

  See `CLAUDE.md` → "Real API Testing Policy" → "Narrow exception".
  """

  @spec gun_upgrade(keyword()) :: {:gun_upgrade, pid(), reference(), [String.t()], list()}
  def gun_upgrade(opts \\ []) do
    opts = Keyword.validate!(opts, conn_pid: self(), stream_ref: make_ref(), headers: [])
    {:gun_upgrade, opts[:conn_pid], opts[:stream_ref], ["websocket"], opts[:headers]}
  end

  @spec gun_ws(keyword()) :: {:gun_ws, pid(), reference(), term()}
  def gun_ws(opts \\ []) do
    opts = Keyword.validate!(opts, conn_pid: self(), stream_ref: make_ref(), frame: {:text, ""})
    {:gun_ws, opts[:conn_pid], opts[:stream_ref], opts[:frame]}
  end

  @spec gun_down(keyword()) :: {:gun_down, pid(), atom(), term(), list()}
  def gun_down(opts \\ []) do
    opts =
      Keyword.validate!(opts, conn_pid: self(), protocol: :http, reason: :normal, killed_streams: [])

    {:gun_down, opts[:conn_pid], opts[:protocol], opts[:reason], opts[:killed_streams]}
  end

  @spec gun_error(keyword()) :: {:gun_error, pid(), reference(), term()}
  def gun_error(opts \\ []) do
    opts = Keyword.validate!(opts, conn_pid: self(), stream_ref: make_ref(), reason: :error)
    {:gun_error, opts[:conn_pid], opts[:stream_ref], opts[:reason]}
  end
end
