alias Credo.Check.Refactor.Nesting

# .credo.exs
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/test/fixtures/"]
      },
      strict: true,
      color: true,
      # ExSlop: 31 default AI-slop checks. ExDNA.Credo: clone diagnostics inline.
      plugins: [{ExSlop, []}],
      checks: [
        # AST clone detection surfaced as Credo issues. Same defaults as the
        # standalone `mix ex_dna --max-clones 0` step (Type I + Type II keep,
        # min_mass 30, Type III off) — see the mix.exs precommit.full comment.
        {ExDNA.Credo, []},

        # Increase cyclomatic complexity threshold from 9 to 11
        # Verified 2026-08-20 against max_complexity: 9 — exactly two sites need it:
        # - config.ex validate/1 cond chain (11)
        # - client.ex handle_info/2 :gun_ws frame routing (10)
        {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 11},

        # Increase nesting depth for test files which need deeper nesting
        # for comprehensive integration testing scenarios
        {Nesting, max_nesting: 3, files: %{included: ["test/"]}},

        # Keep default nesting for lib files
        {Nesting, max_nesting: 2, files: %{included: ["lib/"]}}
      ]
    }
  ]
}
