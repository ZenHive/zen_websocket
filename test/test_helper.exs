# Test Tagging Conventions:
#
# - :integration      - Opt-in extra suite. Excluded from default `mix test` AND
#                       from the coverage gate (`mix test.json --exclude integration
#                       --include external_network`).
# - :external_network - Opens a socket (MockWebSockServer or internet). Excluded
#                       from default `mix test` only; still runs in the coverage gate.
#
# Default: mix test runs only unit tests (no tags, no sockets)
# Full suite: mix test --include integration --include external_network
# External only: mix test --only external_network
#
# Unit tests should be pure function tests with no network/I/O, completing < 30 seconds total.

ExUnit.start(exclude: [:integration, :external_network])
