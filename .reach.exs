# Reach architecture policy — drives `mix reach.check --arch` / `--smells`.
# Single-namespace library: core lib vs reference examples vs test support.
[
  # Reach assigns the first matching layer, so specific namespaces precede
  # the catch-all core pattern.
  layers: [
    examples: "ZenWebsocket.Examples.*",
    support: "ZenWebsocket.Test.Support.*",
    core: "ZenWebsocket.*"
  ],
  # Production core must not depend on reference examples or test support.
  # Testing.Server is the sole exception because it loads the test-only server
  # dynamically while remaining compilable outside MIX_ENV=test.
  deps: [
    forbidden: [
      {:core, :examples},
      {:core, :support,
       except_edges: [
         {"ZenWebsocket.Testing.Server", "ZenWebsocket.Test.Support.MockWebSockServer"}
       ]}
    ]
  ],
  # `--smells` is advisory unless strict is set (reach 2.8.2 config.ex ~L351);
  # this makes every `mix reach.check --arch --smells` invocation gate.
  smells: [strict: true]
]
