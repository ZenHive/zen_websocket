defmodule ZenWebsocket.MixProject do
  use Mix.Project

  @version "0.4.2"

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

      # Test coverage configuration - exclude non-production modules
      # Excludes: Examples (documentation/reference), Test.Support (test infra), Mix.Tasks (CLI)
      test_coverage: [
        ignore_modules: [
          ~r/^ZenWebsocket\.Test\.Support\./,
          ~r/^ZenWebsocket\.Examples\./,
          ~r/^Mix\.Tasks\./
        ]
      ],

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
          "AGENTS.md",
          "docs/Architecture.md",
          "docs/Examples.md",
          "docs/guides/building_adapters.md",
          "docs/guides/performance_tuning.md",
          "docs/guides/troubleshooting_reconnection.md",
          "docs/guides/deployment_considerations.md",
          "docs/architecture/reconnection.md",
          "docs/gun_integration.md",
          "docs/stability_testing.md",
          "docs/supervision_strategy.md"
        ],
        groups_for_extras: [
          "Getting Started": ["README.md", "USAGE_RULES.md", "AGENTS.md", "CHANGELOG.md", "docs/Examples.md"],
          Guides: [
            "docs/guides/building_adapters.md",
            "docs/guides/performance_tuning.md",
            "docs/guides/troubleshooting_reconnection.md",
            "docs/guides/deployment_considerations.md"
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
        "test.json": :test,
        "dialyzer.json": :dev,
        security: :dev
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
      # AI-friendly test output
      {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false},
      # AI-friendly dialyzer output
      {:dialyzer_json, "~> 0.2", only: [:dev, :test], runtime: false},

      # Tidewave for Claude Code MCP integration (non-Phoenix needs bandit)
      {:tidewave, "~> 0.6", only: :dev},
      {:bandit, "~> 1.10", only: :dev},

      # Static code analysis
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # Credo plugin flagging AI-generated-code antipatterns
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},

      # Code analysis tools
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false},
      {:boxart, "~> 0.3.3", only: [:dev, :test], runtime: false},

      # Self-describing APIs — full dep, macros expand at compile time
      {:descripex, "~> 0.11"},

      # Documentation
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      # Tasks
      {:task_validator, "~> 0.9.5", only: [:dev, :test], runtime: false},
      # Usage rules for AI agents and documentation
      {:usage_rules, "~> 1.2", only: :dev, runtime: false},

      # Security scanning
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},

      # Used for mock WebSocket server in tests
      {:cowboy, "~> 2.10", only: :test},

      # WebSock for standardized WebSocket handling (also needed by bandit/tidewave in dev)
      {:websock, "~> 0.5", only: [:dev, :test]},
      {:websock_adapter, "~> 0.5", only: [:dev, :test]},

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
      # OOM mitigation: skip transitive deps (default is :app_tree). Tidewave/bandit's
      # HTTP stack (plug, mint, cowlib, etc.) isn't in lib/'s call graph and bloats the PLT.
      plt_add_deps: :apps_direct,
      # :public_key/:ssl are used directly (reconnection.ex calls :public_key.cacerts_get/0)
      # but aren't listed deps, so :apps_direct would drop them from the PLT.
      plt_add_apps: [:mix, :public_key, :ssl, :crypto],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  defp aliases do
    [
      security: ["sobelow --exit --skip --config"],
      # VibeKit canonical deterministic CI gate (plain test/dialyzer).
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        # preferred_envs (cli/0) is ignored inside alias steps — set MIX_ENV explicitly.
        # `mix cmd` runs System.cmd with no shell, so use `env` to apply the assignment.
        "cmd env MIX_ENV=test mix test --exclude integration",
        # --ignore TagTODO/TagFIXME: tracked-debt visibility via plain `mix credo`,
        # not a gate-blocking regression.
        "credo --strict --ignore TagTODO,TagFIXME",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "dialyzer"
      ],
      # elixir-setup three-tier inner-loop gates (AI-friendly .json reporters).
      "check.fast": [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --ignore TagTODO,TagFIXME"
      ],
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --ignore TagTODO,TagFIXME",
        "doctor --raise",
        "cmd env MIX_ENV=test mix test.json --quiet --cover --cover-threshold 80 --summary-only --exclude integration",
        "sobelow --skip"
      ],
      "precommit.full": ["precommit", "dialyzer.json --quiet"],
      # Tidewave MCP server for Claude Code integration (non-Phoenix)
      tidewave: [
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4001) end)'"
      ]
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
