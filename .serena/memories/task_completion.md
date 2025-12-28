# Task Completion Checklist

## Before Completing Any Task

### 1. Code Quality Checks
```bash
mix format           # Format code
mix lint             # Credo static analysis
mix typecheck        # Dialyzer type checking
mix security         # Sobelow security scan
```

### 2. Run All Tests
```bash
mix test             # All tests must pass
mix test --cover     # Check coverage
```

### 3. Full Quality Gate (Recommended)
```bash
mix check            # Runs lint + typecheck + security + coverage
```

## Code Review Checklist
- [ ] All public functions have `@spec` annotations
- [ ] All modules have `@moduledoc` documentation
- [ ] Functions are ≤15 lines
- [ ] Module has ≤5 functions (for new modules)
- [ ] No mocks used in tests (real API testing only)
- [ ] Error handling uses `{:ok, result} | {:error, reason}`
- [ ] Pattern matching used instead of conditionals where appropriate

## Documentation
- [ ] Update CHANGELOG.md if significant change
- [ ] Update README.md if API changed
- [ ] Update docs/ if architecture changed

## Git Commit
- [ ] Commit message is clear and descriptive
- [ ] Related changes are in single commit
- [ ] No debug code or print statements left

## For Feature Additions
1. Justify the module with real use cases
2. Write tests first (TDD)
3. Implement with max 5 functions
4. Add real API tests (no mocks)
5. Run `mix check`
6. Update architecture documentation
