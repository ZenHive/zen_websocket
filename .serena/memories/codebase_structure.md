# Codebase Structure

## Foundation Modules (8 core - complete)
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
```

## Enhancement Modules (financial infrastructure)
```
├── rate_limiter.ex        # API rate limit management
├── client_supervisor.ex   # Client supervision
```

## Example Adapters
```
└── examples/
    ├── deribit_adapter.ex          # Deribit platform integration
    ├── deribit_genserver_adapter.ex # GenServer-based Deribit adapter
    ├── deribit_rpc.ex              # Deribit RPC helpers
    ├── adapter_supervisor.ex       # Adapter supervision
    ├── batch_subscription_manager.ex # Batch subscriptions
    ├── supervised_client.ex        # Supervised client example
    ├── platform_adapter_template.ex # Template for new adapters
    ├── usage_patterns.ex           # Usage pattern examples
    └── docs/                       # Documentation examples
        ├── basic_usage.ex
        ├── json_rpc_client.ex
        ├── error_handling.ex
        └── subscription_management.ex
```

## Helpers
```
└── helpers/
    └── deribit.ex         # Deribit-specific helpers
```

## Mix Tasks
```
lib/mix/tasks/
├── stability_test.ex              # Stability testing task
├── zen_websocket.usage.ex         # Usage rules task
└── zen_websocket.validate_usage.ex # Validate usage task
```

## Test Structure
```
test/
├── zen_websocket/         # Core module tests
├── integration/           # Real API integration tests
└── support/               # Shared test infrastructure
    ├── MockWebSockServer  # Controlled WebSocket server
    ├── CertificateHelper  # TLS certificate generation
    ├── NetworkSimulator   # Network condition simulation
    └── TestEnvironment    # Environment management
```

## Configuration Files
- `mix.exs` - Project configuration
- `.credo.exs` - Credo configuration
- `.formatter.exs` - Code formatter config
- `.dialyzer_ignore.exs` - Dialyzer ignores
- `config/` - Runtime configuration
