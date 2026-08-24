# ZenWebsocket Examples

Practical examples of using ZenWebsocket, all written and tested in-tree under
`lib/zen_websocket/examples/`. Examples and their test suites live in the library
repository; a separate `examples/<name>/` mix project structure was evaluated and
reverted in favor of in-tree examples to ensure they stay synchronized with the
library. This page is a navigable index; each entry points at the module source
and test, which are the single source of truth rather than pasting code blocks
that can drift.

## Module Index

### `lib/zen_websocket/examples/`

| Module | File | Demonstrates | Tests |
|---|---|---|---|
| `ZenWebsocket.Examples.AdapterSupervisor` | [adapter_supervisor.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/adapter_supervisor.ex) | Supervising adapter GenServers alongside `ClientSupervisor` | none |
| `ZenWebsocket.Examples.BatchSubscriptionManager` | [batch_subscription_manager.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/batch_subscription_manager.ex) | Batching subscription requests with configurable batch size/delay | [batch_subscription_manager_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/batch_subscription_manager_test.exs) |
| `ZenWebsocket.Examples.DeribitAdapter` | [deribit_adapter.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/deribit_adapter.ex) | Simplified Deribit adapter built on `DeribitRpc` | [deribit_adapter_auth_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/deribit_adapter_auth_test.exs), [deribit_adapter_nil_client_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/deribit_adapter_nil_client_test.exs) |
| `ZenWebsocket.Examples.DeribitGenServerAdapter` | [deribit_genserver_adapter.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/deribit_genserver_adapter.ex) | Production-ready supervised Deribit adapter: monitored client, auto-reconnect, auth/subscription restore | [deribit_genserver_adapter_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/deribit_genserver_adapter_test.exs) |
| `ZenWebsocket.Examples.DeribitRpc` | [deribit_rpc.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/deribit_rpc.ex) | Shared Deribit JSON-RPC method/request builders used by both Deribit adapters | none dedicated — exercised indirectly through the `DeribitAdapter`/`DeribitGenServerAdapter` test suites |
| `ZenWebsocket.Examples.JsonRpcTransport` | [json_rpc_transport.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/json_rpc_transport.ex) | Shared JSON-RPC send helper (`Client.send_message/2` result normalization) used by both Deribit adapters | none dedicated — exercised indirectly via [deribit_adapter_nil_client_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/deribit_adapter_nil_client_test.exs) |
| `ZenWebsocket.Examples.PlatformAdapterTemplate` | [platform_adapter_template.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/platform_adapter_template.ex) | Minimal template (`connect/2`, `authenticate/2`, extension points) for a new platform adapter | [platform_adapter_template_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/platform_adapter_template_test.exs) |
| `ZenWebsocket.Examples.SupervisedClient` | [supervised_client.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/supervised_client.ex) | Minimal `ClientSupervisor`-based connection supervision | [supervised_client_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/supervised_client_test.exs) |
| `ZenWebsocket.Examples.UsagePatterns` | [usage_patterns.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/usage_patterns.ex) | Three usage patterns: direct connection, `ClientSupervisor`, direct supervision in your own tree | none |

`ClientSupervisor` itself (not an example module, but exercised by this
directory's supervision examples) has end-to-end coverage in
[supervised_connection_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/supervised_connection_test.exs).

### `lib/zen_websocket/examples/docs/`

A second set of examples, written to accompany this guide's code snippets:

| Module | File | Demonstrates | Tests |
|---|---|---|---|
| `ZenWebsocket.Examples.Docs.BasicUsage` | [basic_usage.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/docs/basic_usage.ex) | Basic connect + request/response against Deribit testnet | [basic_usage_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/basic_usage_test.exs) |
| `ZenWebsocket.Examples.Docs.ErrorHandling` | [error_handling.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/docs/error_handling.ex) | A GenServer wrapping a connection with retry-on-failure | [error_handling_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/error_handling_test.exs) |
| `ZenWebsocket.Examples.Docs.JsonRpcClient` | [json_rpc_client.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/docs/json_rpc_client.ex) | Declaring JSON-RPC methods with `ZenWebsocket.JsonRpc`'s `defrpc` macro | none |
| `ZenWebsocket.Examples.Docs.SubscriptionManagement` | [subscription_management.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/docs/subscription_management.ex) | Multi-channel subscription patterns | [subscription_management_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/subscription_management_test.exs) |

## Running the Examples

```bash
# Run a single example's test
mix test test/zen_websocket/examples/basic_usage_test.exs

# Run every example test
mix test test/zen_websocket/examples/

# Run with coverage
mix test --cover test/zen_websocket/examples/

# Or explore interactively
iex -S mix
```

```elixir
# In IEx, try the basic usage example
alias ZenWebsocket.Examples.Docs.BasicUsage

{:ok, client} = BasicUsage.deribit_testnet_example()
```

## Deribit Integration

`ZenWebsocket.Examples.DeribitAdapter` and `ZenWebsocket.Examples.DeribitGenServerAdapter`
are the in-tree Deribit integration examples — authentication, subscription
management, and (for the GenServer adapter) monitored auto-reconnect with
auth/subscription restore. Both share request-building through `DeribitRpc` and
transport through `JsonRpcTransport`. Study
[deribit_genserver_adapter.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/deribit_genserver_adapter.ex)
for the production-supervised pattern. Its test suite
([deribit_genserver_adapter_test.exs](https://github.com/ZenHive/zen_websocket/blob/main/test/zen_websocket/examples/deribit_genserver_adapter_test.exs))
runs against real Deribit testnet endpoints — all integration tests in this library
use live API endpoints rather than mocks to ensure correctness against real
provider behavior.

## Extending for Your Platform

To create an adapter for your own platform:

1. Study [platform_adapter_template.ex](https://github.com/ZenHive/zen_websocket/blob/main/lib/zen_websocket/examples/platform_adapter_template.ex)
2. Follow the [adapter building guide](guides/building_adapters.md)
3. Implement platform-specific authentication, message formatting, subscription
   management, and error handling
4. Add tests against real API endpoints — see the Deribit adapters' test suites
   for the pattern
5. Document platform-specific features

## Additional Resources

- [Architecture Overview](Architecture.md)
- [Building Custom Adapters](guides/building_adapters.md)
- [Troubleshooting Reconnection](guides/troubleshooting_reconnection.md)
- [API Documentation](https://hexdocs.pm/zen_websocket)
