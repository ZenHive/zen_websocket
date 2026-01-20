# Test Coverage Roadmap

This document tracks test coverage improvements for ZenWebsocket.

## Coverage Configuration

**Excluded modules** (via `mix.exs` `test_coverage` config):
- `ZenWebsocket.Test.Support.*` - Test infrastructure
- `ZenWebsocket.Examples.*` - Documentation examples
- `Mix.Tasks.*` - CLI utilities

Run `mix test --cover` to see current coverage.

## Known Coverage Gaps

| Module | Gap Analysis |
|--------|--------------|
| Client | Core GenServer - needs integration tests |
| HeartbeatManager | GenServer callbacks need integration tests |
| MessageHandler | Some message routing paths |
| Reconnection | `establish_connection/1` needs integration tests |
| Helpers.Deribit | Platform-specific helpers |
| Debug | Logging utilities (low priority) |

## Test Categories

### Unit Tests (Fast, No Network)
Tests for pure functions that don't require network or external services.

**Files:**
- `test/zen_websocket/frame_test.exs`
- `test/zen_websocket/config_test.exs`
- `test/zen_websocket/reconnection_test.exs`
- `test/zen_websocket/json_rpc_test.exs`
- `test/zen_websocket/error_handler_test.exs`
- `test/zen_websocket/rate_limiter_test.exs`

### Integration Tests (MockWebSockServer)
Tests using local mock WebSocket server for controlled scenarios.

**Tagged:** `@tag :integration`
**Run:** `mix test.json --quiet --include integration`

**Files:**
- `test/integration/client_integration_test.exs`
- `test/integration/heartbeat_integration_test.exs`
- `test/integration/reconnection_integration_test.exs`

### External Network Tests (Deribit Testnet)
Tests against real external APIs.

**Tagged:** `@tag :external_network`
**Run:** `mix test.json --quiet --include external_network`
**Requires:** `DERIBIT_CLIENT_ID` and `DERIBIT_CLIENT_SECRET` env vars

## Prioritized Test Tasks

### Immediate (Before v0.2.0)

| Task | D/B | Priority | Status |
|------|-----|----------|--------|
| T001: Configure coverage exclusions | 1/8 | 8.0 | ✅ |
| T002: Frame edge case tests | 2/5 | 2.5 | ✅ |
| T003: Config boundary value tests | 2/4 | 2.0 | ✅ |
| T004: Reconnection extreme value tests | 2/4 | 2.0 | ✅ |

### Medium Term (v0.3.0)

| Task | D/B | Priority | Status |
|------|-----|----------|--------|
| T005: Property-based tests (R010) | 4/6 | 1.5 | ⬜ |
| T006: Client GenServer integration tests | 5/7 | 1.4 | ⬜ |
| T007: HeartbeatManager integration tests | 4/5 | 1.25 | ⬜ |
| T008: MessageHandler routing tests | 3/4 | 1.3 | ⬜ |

### Future Enhancements

| Task | D/B | Priority | Status |
|------|-----|----------|--------|
| T009: Debug module tests | 2/2 | 1.0 | ⬜ |
| T010: Helpers.Deribit tests | 3/3 | 1.0 | ⬜ |
| T011: Stress testing (R016) | 5/6 | 1.2 | ⬜ |

## Test Writing Guidelines

### Unit Tests
- No network, no external services
- Pure function testing
- Fast execution (<100ms per test)
- Edge cases and boundary values

### Integration Tests
- Use `MockWebSockServer` for controlled scenarios
- Test real GenServer behavior
- Connection lifecycle testing
- Error recovery scenarios

### External Tests
- Real API calls (testnet only)
- Require credentials via env vars
- Mark with `@tag :external_network`
- Handle rate limiting gracefully

## Running Tests

```bash
# Quick check (unit tests only)
mix test.json --quiet --summary-only

# With coverage
mix test.json --quiet --cover

# Include integration tests
mix test.json --quiet --include integration

# Include external network tests
mix test.json --quiet --include external_network

# All tests
mix test.json --quiet --include integration --include external_network
```
