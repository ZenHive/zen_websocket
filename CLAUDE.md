# CLAUDE.md

@include ~/.claude/includes/across-instances.md
@include ~/.claude/includes/critical-rules.md
@include ~/.claude/includes/task-prioritization.md
@include ~/.claude/includes/task-writing.md
@include ~/.claude/includes/web-command.md
@include ~/.claude/includes/code-style.md
@include ~/.claude/includes/development-philosophy.md
@include ~/.claude/includes/documentation-guidelines.md
@include ~/.claude/includes/api-integration.md
@include ~/.claude/includes/development-commands.md
@include ~/.claude/includes/elixir-patterns.md
@include ~/.claude/includes/library-design.md

---

## Project Overview

**ZenWebsocket** is a robust WebSocket client library for Elixir, specifically designed for financial APIs (particularly Deribit cryptocurrency trading). Built on Gun transport with 8 foundation modules, enhanced with critical financial infrastructure.

**Financial Development Principle**: Start simple, add complexity only when necessary based on real data.

## Project-Specific Commands

```bash
# Code Quality (project aliases)
mix lint          # Credo strict mode
mix typecheck     # Dialyzer
mix security      # Sobelow
mix check         # All quality checks (lint + typecheck + security + coverage)
mix rebuild       # Full rebuild with all checks

# Testing
mix test.api              # Real API integration tests
mix test.api --deribit    # Deribit-specific tests
mix test.performance      # Performance/stress testing
```

## Architecture

### Module Structure
```
lib/zen_websocket/
├── client.ex              # Main client interface (5 public functions)
├── config.ex              # Configuration struct and validation
├── frame.ex               # WebSocket frame encoding/decoding
├── connection_registry.ex # ETS-based connection tracking
├── reconnection.ex        # Exponential backoff retry logic
├── message_handler.ex     # Message parsing and routing
├── error_handler.ex       # Error categorization and recovery
├── json_rpc.ex           # JSON-RPC 2.0 protocol support
├── correlation_manager.ex # Request/response correlation
├── rate_limiter.ex        # API rate limit management
└── examples/
    └── deribit_adapter.ex # Deribit platform integration
```

### Public API (5 Functions)
```elixir
ZenWebsocket.Client.connect(url, opts)
ZenWebsocket.Client.send_message(client, message)
ZenWebsocket.Client.close(client)
ZenWebsocket.Client.subscribe(client, channels)
ZenWebsocket.Client.get_state(client)
```

### Project Constraints
- Maximum 5 functions per module (new modules)
- Maximum 15 lines per function
- Direct Gun API usage - no wrapper layers
- Real API testing only - zero mocks

## Configuration

### Environment Setup
```bash
export DERIBIT_CLIENT_ID="your_client_id"
export DERIBIT_CLIENT_SECRET="your_client_secret"
```

### ZenWebsocket.Config Options
- `url` - WebSocket endpoint URL
- `headers` - Connection headers
- `timeout` - Connection timeout (default: 5000ms)
- `retry_count` - Maximum retry attempts (default: 3)
- `retry_delay` - Initial retry delay (default: 1000ms)
- `heartbeat_interval` - Ping interval (default: 30000ms)

## Testing Strategy

### Real API Testing Policy
**NO MOCKS ALLOWED** - Only real API testing:
- `test.deribit.com` for Deribit integration
- Local mock servers using `MockWebSockServer`
- Real network conditions and error scenarios

**Rationale**: Financial software requires testing against real conditions. Mocks hide edge cases that cause financial losses.

### Test Support Modules
- `MockWebSockServer` - Controlled WebSocket server
- `CertificateHelper` - TLS certificate generation
- `NetworkSimulator` - Network condition simulation
- `TestEnvironment` - Environment management

## WebSocket Connection Architecture

### Connection Model
- WebSocket connections are Gun processes managed by `ZenWebsocket.Client`
- Connection processes monitored via `Process.monitor/1`
- Failures classified by exit reasons

### Reconnection Pattern
```elixir
{:ok, client} = ZenWebsocket.Client.connect(url, [
  timeout: 5000,
  retry_count: 3,
  retry_delay: 1000,
  heartbeat_interval: 30000
])
```

## Platform Integration

### Deribit Adapter
Located in `lib/zen_websocket/examples/deribit_adapter.ex`:
- Authentication flow
- Subscription management
- Heartbeat/test_request handling
- JSON-RPC 2.0 formatting
- Cancel-on-disconnect protection

**Supervised Pattern (production):**
```elixir
connect_opts = [
  reconnect_on_error: false,  # Adapter handles reconnection
  heartbeat_config: %{...}
]
```

**Standalone Pattern (simple use):**
```elixir
{:ok, client} = Client.connect(url)  # reconnect_on_error: true (default)
```

## Key Dependencies

### Core Runtime
- `gun ~> 2.2` - HTTP/2 and WebSocket client
- `jason ~> 1.4` - JSON encoding/decoding
- `telemetry ~> 1.3` - Metrics and monitoring

### Development
- `credo`, `dialyxir`, `sobelow`, `ex_doc`

### Testing
- `cowboy ~> 2.10`, `websock ~> 0.5`, `stream_data ~> 1.0`, `x509 ~> 0.8`

## Task Management

### Task ID Format
Use `WNX####` format:
- Core: WNX0001-WNX0099
- Features: WNX0100-WNX0199
- Docs: WNX0200-WNX0299
- Tests: WNX0300-WNX0399

### Task Tracking
Tasks tracked in `docs/TaskList.md` with status values:
- `Planned`, `In Progress`, `Review`, `Completed`, `Blocked`

Priority values:
- `Critical`, `High`, `Medium`, `Low`

### WebSocket-Specific Requirements
- All connection tasks must include real API testing
- Platform integration tasks reference Deribit adapter patterns
- Frame handling tasks include malformed data testing
- Reconnection tasks test real network interruptions
