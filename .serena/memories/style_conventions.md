# Code Style and Conventions

## Module Structure
- Maximum 5 functions per module (for new modules)
- Maximum 15 lines per function
- Maximum 2 levels of function call depth

## Documentation Style
Concise, optimized documentation:

```elixir
@moduledoc """
WebSocket client for real-time cryptocurrency trading APIs.

- Uses Gun transport for WebSocket connections
- Handles automatic reconnection with exponential backoff
"""

@doc """
Connects to WebSocket endpoint with configuration options.

Returns client struct for subsequent operations.
"""
```

## Function Structure
Use `with` for multi-step operations:

```elixir
def connect(%Config{url: url} = config, opts \\ []) do
  with {:ok, gun_pid} <- open_connection(url, opts),
       {:ok, stream_ref} <- upgrade_to_websocket(gun_pid, headers),
       :ok <- await_upgrade(gun_pid, stream_ref, timeout) do
    {:ok, %Client{gun_pid: gun_pid, stream_ref: stream_ref}}
  end
end
```

## Error Handling
- Pass raw errors without wrapping
- Use `{:ok, result} | {:error, reason}` pattern
- Apply "let it crash" philosophy
- Pattern match on error types

```elixir
def handle_error({:error, error}) do
  case error do
    {:timeout, _} -> handle_timeout()
    {:connection_refused, _} -> handle_refused()
    _ -> {:error, :unknown}
  end
end
```

## Type Specifications
- All public functions must have `@spec` annotations
- All modules must have `@moduledoc` documentation

## When to Use GenServers
**Use GenServers for:**
- Receiving async messages (Gun WebSocket frames)
- Maintaining state (connections, subscriptions)
- Coordinating concurrent access (rate limiting)

**Use pure functions/ETS for:**
- Stateless transformations (frame encoding)
- Simple lookups (connection registry)

## Anti-Patterns to Avoid
- No premature optimization
- No "just-in-case" code
- No abstractions without 2+ concrete use cases
- No complex macros unless necessary
