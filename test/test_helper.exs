# Test Tagging Conventions:
#
# - :integration      - Tests using MockWebSockServer, Gun, or external APIs
# - :external_network - Tests requiring internet (Deribit testnet, echo.websocket.org, etc.)
#
# Default: mix test runs only unit tests (no tags, no sockets)
# Full suite: mix test --include integration --include external_network
# External only: mix test --only external_network
#
# Unit tests should be pure function tests with no network/I/O, completing < 30 seconds total.

ExUnit.start(exclude: [:integration, :external_network])
