# Suggested Commands for ZenWebsocket Development

## Core Development
```bash
mix compile          # Compile the project
mix test             # Run test suite (93 tests, all real APIs)
mix test --cover     # Run tests with coverage
mix coverage         # Alias for test with coverage
```

## Code Quality
```bash
mix lint             # Credo static analysis (strict mode)
mix typecheck        # Dialyzer type checking
mix security         # Sobelow security analysis
mix check            # ALL quality checks (lint + typecheck + security + coverage)
mix rebuild          # Full rebuild (clean deps, recompile, run all checks)
```

## Documentation
```bash
mix docs             # Generate documentation
```

## Testing
```bash
mix test.api              # Real API integration tests
mix test.api --deribit    # Deribit-specific API tests
mix test.performance      # Performance and stress testing
```

## Formatting
```bash
mix format           # Format code
mix format --check-formatted  # Check if formatted
```

## System Utilities (Darwin/macOS)
```bash
git status           # Check git status
git diff             # View changes
ls -la               # List files
find . -name "*.ex"  # Find Elixir files
grep -r "pattern" lib/  # Search in lib
```

## IEx Console
```bash
iex -S mix           # Start IEx with project loaded
```
