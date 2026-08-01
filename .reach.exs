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
  ],
  # `--smells` is advisory unless strict is set (reach 2.8.2 config.ex ~L351);
  # this makes every `mix reach.check --arch --smells` invocation gate.
  smells: [strict: true]
]
