# ZenWebsocket Project Overview

## Purpose
ZenWebsocket is a robust WebSocket client library for Elixir, designed for financial APIs (particularly Deribit cryptocurrency trading). Built on Gun transport for production-grade reliability.

## Tech Stack
- **Language**: Elixir ~> 1.15
- **WebSocket Transport**: Gun ~> 2.2
- **JSON**: Jason ~> 1.4
- **Monitoring**: Telemetry ~> 1.3
- **TLS**: Certifi ~> 2.5

## Development Dependencies
- **Static Analysis**: Credo ~> 1.7
- **Type Checking**: Dialyxir ~> 1.4
- **Security**: Sobelow ~> 0.13
- **Documentation**: ExDoc ~> 0.31
- **Testing**: Cowboy, WebSock, StreamData, X509

## Core Design Principles
1. **Simplicity First**: Start simple, add complexity only when necessary
2. **Real API Testing**: NO MOCKS ALLOWED - all tests use real APIs
3. **Maximum 5 functions per module**
4. **Maximum 15 lines per function**
5. **Maximum 2 levels of function call depth**
6. **Use GenServers for state/message handling, pure functions for stateless ops**

## Public API (5 Functions)
```elixir
ZenWebsocket.Client.connect(url, opts)
ZenWebsocket.Client.send_message(client, message)
ZenWebsocket.Client.close(client)
ZenWebsocket.Client.subscribe(client, channels)
ZenWebsocket.Client.get_state(client)
```

## Environment Variables
```bash
export DERIBIT_CLIENT_ID="your_client_id"
export DERIBIT_CLIENT_SECRET="your_client_secret"
```
