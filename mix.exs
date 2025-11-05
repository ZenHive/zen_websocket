defmodule ZenWebsocket.MixProject do
  use Mix.Project

  @version "0.1.4"

  def project do
    [
      app: :zen_websocket,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),

      # Hex Package metadata
      description: description(),
      package: package(),

      # Docs
      name: "ZenWebsocket",
      source_url: "https://github.com/ZenHive/zen_websocket",
      homepage_url: "https://github.com/ZenHive/zen_websocket",
      docs: [
        main: "ZenWebsocket",
        extras: [
          "README.md",
          "CHANGELOG.md",
          "USAGE_RULES.md",
          "docs/Architecture.md",
          "docs/Examples.md",
          "docs/guides/building_adapters.md",
          "docs/guides/troubleshooting_reconnection.md",
          "docs/architecture/reconnection.md",
          "docs/gun_integration.md",
          "docs/stability_testing.md",
          "docs/supervision_strategy.md"
        ],
        groups_for_extras: [
          "Getting Started": ["README.md", "USAGE_RULES.md", "CHANGELOG.md", "docs/Examples.md"],
          Guides: [
            "docs/guides/building_adapters.md",
            "docs/guides/troubleshooting_reconnection.md"
          ],
          Architecture: [
            "docs/Architecture.md",
            "docs/architecture/reconnection.md",
            "docs/gun_integration.md",
            "docs/supervision_strategy.md"
          ],
          Testing: ["docs/stability_testing.md"]
        ],
        source_url: "https://github.com/ZenHive/zen_websocket",
        source_ref: "v#{@version}"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        dialyzer: :dev,
        credo: :dev,
        sobelow: :dev,
        lint: :dev,
        typecheck: :dev,
        security: :dev,
        coverage: :test,
        check: :dev,
        docs: :dev
      ]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :ssl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Runtime dependencies
      {:gun, "~> 2.2"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.3"},
      {:certifi, "~> 2.5"},

      # Development and test dependencies
      # Static code analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.22.0", only: :dev},
      # Tasks
      {:task_validator, "~> 0.9.5", only: [:dev, :test], runtime: false},
      # Usage rules for AI agents and documentation
      {:usage_rules, "~> 0.1", only: :dev, runtime: false},

      # Security scanning
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},

      # Used for mock WebSocket server in tests
      {:cowboy, "~> 2.10", only: :test},

      # WebSock for standardized WebSocket handling
      {:websock, "~> 0.5", only: :test},
      {:websock_adapter, "~> 0.5", only: :test},

      # Required for Plug.Cowboy.http/3
      {:plug_cowboy, "~> 2.6", only: :test},
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:styler, "~> 1.4", only: [:dev, :test], runtime: false},

      # For generating temporary files (certificates) in tests
      {:temp, "~> 0.4", only: :test},

      # For generating self-signed certificates in tests
      {:x509, "~> 0.8", only: :test}
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  # Add aliases for code quality tools
  defp aliases do
    [
      lint: ["mix format && credo --strict"],
      typecheck: ["dialyzer"],
      security: ["sobelow --exit --config"],
      coverage: ["test --cover"],
      docs: ["docs"],
      check: [
        "lint",
        "typecheck",
        "security",
        "coverage"
      ],
      rebuild: ["deps.clean --all", "clean", "deps.get", "compile", "dialyzer", "credo --strict"]
    ]
  end

  defp description do
    """
    A robust WebSocket client library for Elixir, built on Gun transport for production-grade
    reliability. Designed for financial APIs with automatic reconnection, comprehensive error
    handling, and real-world testing.
    """
  end

  defp package do
    [
      name: "zen_websocket",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* USAGE_RULES*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/ZenHive/zen_websocket",
        "Docs" => "https://hexdocs.pm/zen_websocket"
      },
      maintainers: ["ZenHive"]
    ]
  end
end
