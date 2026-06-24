# Reach architecture policy — drives `mix reach.check --arch` / `--smells`.
# Single-namespace library: core lib vs reference examples vs test support.
[
  layers: [
    core: "ZenWebsocket.*",
    examples: "ZenWebsocket.Examples.*",
    support: "ZenWebsocket.Test.Support.*"
  ],
  # Production core must not depend on reference examples or test support.
  deps: [
    forbidden: [
      {:core, :examples},
      {:core, :support}
    ]
  ]
]
