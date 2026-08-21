defmodule ZenWebsocket.MixProject do
  use Mix.Project

  @version "0.7.0"

  # Core-only coverage floor. Measured 2026-08-21 via
  # `mix test.json --cover --exclude integration --include local_network`
  # after excluding `test_coverage: ignore_modules` (90.34%), rounded down.
  # Raise in lockstep with real core coverage; never pad it.
  @core_cover_threshold 90

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
        ignore_modules: coverage_ignore_modules()
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
          ]
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
      # Bound raised 2.2 -> 2.4: gun 2.4.0 (2026-06-08) is the release that fixes
      # GHSA-w4f7-4cxr-rv3c (CVE-2026-43966, HTTP request/response splitting).
      # `~> 2.2` merely PERMITTED the patched version; `~> 2.4` REQUIRES it, so
      # a fresh install/lock can no longer silently resolve a vulnerable gun.
      {:gun, "~> 2.4"},
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
      # Reach 2.8.2 caps ex_ast at ~> 0.12.0; Reach uses APIs retained by ex_ast 0.13.
      {:ex_ast, "~> 0.13", override: true, only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false},
      {:boxart, "~> 0.3.3", only: [:dev, :test], runtime: false},

      # Self-describing APIs — full dep, macros expand at compile time.
      # Three-segment on purpose (caps at < 0.13.0): descripex 0.12.0 changed
      # `short_name` in describe/1 output from atom to string at a *minor*
      # bump, which the previous `~> 0.11` would have absorbed silently. A 0.x
      # package that breaks on minor earns the tighter form; raise the cap
      # deliberately after reading its CHANGELOG.
      {:descripex, "~> 0.12.0"},

      # Documentation
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
      # Tasks
      {:task_validator, "~> 0.9.5", only: [:dev, :test], runtime: false},
      # Usage rules for AI agents and documentation
      {:usage_rules, "~> 1.2", only: :dev, runtime: false},

      # Security scanning
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
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
      # elixir-setup three-tier inner-loop gates (AI-friendly .json reporters).
      "check.fast": [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --ignore TagTODO,TagFIXME"
      ],
      # Fast local pre-commit loop — skips the cold-PLT dialyzer and the full
      # deps audit so it stays quick on incremental edits.
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --ignore TagTODO,TagFIXME",
        "doctor --raise",
        # Coverage floor: core library only. Measured 2026-08-21 via
        # `mix test.json --cover --exclude integration --include local_network`
        # after excluding `test_coverage: ignore_modules` (90.34%), rounded
        # down. Mock-server tests tagged during the network-tag hygiene pass
        # also carry `:local_network`; including that tag retains their
        # contribution without adding sockets to the default suite. The prior
        # 58% floor measured the diluted suite (Examples.*/Mix.Tasks.* regexes
        # in ignore_modules were a no-op for ex_unit_json 0.6.0, which only
        # matches module atoms). This is a ratchet: it reflects real,
        # currently-passing core coverage, so it will fail on a genuine
        # regression. Raise it as real core coverage grows; never pad it.
        "cmd env MIX_ENV=test mix test.json --quiet --cover --cover-threshold #{@core_cover_threshold} --summary-only --exclude integration --include local_network",
        "sobelow --skip --exit low"
      ],
      # Comprehensive gate — the harness reviewer's `check_command` and `mix ci`
      # target.
      "precommit.full": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --ignore TagTODO,TagFIXME",
        "doctor --raise",
        # Zero-clone budget. This is Type I + Type II with literal_mode: :keep,
        # min_mass 30, Type III off. It is not a byte-identical-function
        # detector: comments add no mass; fragments under 30 AST nodes are
        # invisible (callback wrapper mass 22–26; heartbeat if-block mass 22);
        # larger functions still miss when the AST differs after Type-II keep
        # (__MODULE__ vs alias, local vs remote call, reversed args —
        # build_client_struct/2 was mass 35–36 and silent). The same defaults
        # apply to ExDNA.Credo in .credo.exs, so mix ci runs this filter twice
        # without broadening it. Green means nothing crossed that boundary.
        "ex_dna --max-clones 0",
        "reach.check --arch --smells",
        "sobelow --skip --exit low",
        "deps.audit.gated",
        # preferred_envs (cli/0) is ignored inside alias steps — set MIX_ENV explicitly.
        # `mix cmd` runs System.cmd with no shell, so use `env` to apply the assignment.
        # Coverage floor rationale: see the `precommit` alias above — same
        # measured, ratcheted core-only floor, kept in sync via
        # `@core_cover_threshold`.
        #
        # NO `--summary-only` here, deliberately — unlike the fast `precommit`
        # alias above. This is the alias CI runs, and `--summary-only` omits the
        # failure entries from the emitted JSON: run 30740941359 reported
        # `"failed": 1` and nothing whatsoever about WHICH test, leaving the only
        # route to the identity "edit the alias and push again". The flag saves
        # nothing in CI (the log is machine-read, not human-scrolled) and costs
        # the entire diagnosis. Locally the hooks already print per-file detail,
        # so `precommit` keeps it.
        "cmd env MIX_ENV=test mix test.json --quiet --cover --cover-threshold #{@core_cover_threshold} --exclude integration --include local_network",
        # Dialyzer runs in MIX_ENV=dev, not the canonical bare `dialyzer` step:
        # under :test, the test-only HTTP/mock stack (cowboy, plug_cowboy,
        # websock, x509, temp, stream_data) joins :apps_direct's analyzed set
        # and bloats the PLT with false unknown_function warnings. Dev matches
        # this repo's OOM-tuned PLT design (see `defp dialyzer` above) and the
        # dialyzer.json preferred env.
        "cmd env MIX_ENV=dev mix dialyzer",
        # AGENTS.md is what the cross-family (codex/cursor/grok) reviewers read;
        # a stale render makes them gate against rules that already changed.
        "agents.check"
      ],
      # Fails when AGENTS.md has drifted from CLAUDE.md. Compares rendered output,
      # not mtimes, so drift in a transitive @-import is caught too.
      "agents.check": [
        &agents_check/1
      ],
      # mix_audit discards its own sync exit status (mirego/mix_audit#61), so a
      # frozen advisory DB still reports "No vulnerabilities found" and exits 0.
      # Prove freshness first, then audit. `.mix_audit_ignore` carries the one
      # verified false positive (GHSA-w4f7-4cxr-rv3c on gun — see the file).
      "deps.audit.gated": [
        &advisory_freshness/1,
        "deps.audit --ignore-file .mix_audit_ignore"
      ],
      ci: ["precommit.full"],
      # Stable name the harness reviewer is told to run (`check_command`).
      # Aliased rather than registered as `mix ci` so the dispatch gate can
      # diverge from the local one later without re-registering the project.
      "check.dispatch": ["precommit.full"],
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
      # `lib` intentionally ships the documented example modules and
      # Mix.Tasks.ZenWebsocket.* commands as consumer-visible package content.
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG* USAGE_RULES*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/ZenHive/zen_websocket",
        "Docs" => "https://hexdocs.pm/zen_websocket"
      },
      maintainers: ["ZenHive"]
    ]
  end

  # Both gates below shell out to scripts that live OUTSIDE this repo, on the
  # developer host: the AGENTS.md renderer needs the claude-marketplace
  # checkout plus ~/.claude/includes, and the advisory-freshness prover needs
  # the local mix_audit mirror. Neither exists on a CI runner, and `mix cmd`
  # with an absent path exits non-zero — which aborted the whole `mix ci`
  # alias, and since these steps precede test.json/dialyzer it took the test,
  # coverage and dialyzer signal down with it. Skip loudly when the script is
  # absent so CI keeps running the checks it CAN run; the developer host and
  # the harness reviewer still get the full gate.
  @spec agents_check([String.t()]) :: :ok
  defp agents_check(_args) do
    host_script(
      "~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh",
      ["--check"],
      "AGENTS.md freshness check"
    )
  end

  @spec advisory_freshness([String.t()]) :: :ok
  defp advisory_freshness(_args) do
    host_script(
      "~/_DATA/code/onchain-stack/bin/advisory-freshness.sh",
      [],
      "advisory-mirror freshness check"
    )
  end

  # Mix.Tasks.Test.Coverage matches regexes and atoms (`ignored_any?/2`).
  # ex_unit_json 0.6.0 only does `mod in ignore_modules`, so regexes are
  # no-ops for `mix test.json --cover`. Keep the regexes as the Mix contract
  # and list matching atoms so the JSON coverage gate measures core only.
  # Completeness is asserted in mix_project_test.exs.
  @spec coverage_ignore_modules() :: [module() | Regex.t()]
  defp coverage_ignore_modules do
    [
      ~r/^ZenWebsocket\.Test\.Support\./,
      ~r/^ZenWebsocket\.Examples\./,
      ~r/^Mix\.Tasks\./,
      Mix.Tasks.ZenWebsocket.Usage,
      Mix.Tasks.ZenWebsocket.ValidateUsage,
      ZenWebsocket.Examples.AdapterSupervisor,
      ZenWebsocket.Examples.BatchSubscriptionManager,
      ZenWebsocket.Examples.DeribitAdapter,
      ZenWebsocket.Examples.DeribitGenServerAdapter,
      ZenWebsocket.Examples.DeribitRpc,
      ZenWebsocket.Examples.Docs.BasicUsage,
      ZenWebsocket.Examples.Docs.ErrorHandling,
      ZenWebsocket.Examples.Docs.JsonRpcClient,
      ZenWebsocket.Examples.Docs.SubscriptionManagement,
      ZenWebsocket.Examples.JsonRpcTransport,
      ZenWebsocket.Examples.PlatformAdapterTemplate,
      ZenWebsocket.Examples.SupervisedClient,
      ZenWebsocket.Examples.UsagePatterns,
      ZenWebsocket.Examples.UsagePatterns.ExampleApp
    ]
  end

  @spec host_script(String.t(), [String.t()], String.t()) :: :ok
  defp host_script(path, args, label) do
    expanded = Path.expand(path)

    if File.exists?(expanded) do
      {_out, status} =
        System.cmd(expanded, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)

      if status != 0 do
        Mix.raise("#{label} failed (#{expanded} exited #{status})")
      end
    else
      Mix.shell().info("[skip] #{label}: #{expanded} not found (developer-host script, absent in CI).")
    end

    :ok
  end
end
