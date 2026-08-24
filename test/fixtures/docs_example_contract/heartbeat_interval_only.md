# Fixture: the 0.7.1 docs defect where `heartbeat_interval` was passed to
# `Client.connect/2` without `heartbeat_config`. HeartbeatManager.start_timer/1
# leaves the state unchanged when heartbeat_config is `:disabled`.

```elixir
{:ok, client} = ZenWebsocket.Client.connect("wss://example.com/ws", heartbeat_interval: 30_000)
```
