# .credo.exs
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      color: true,
      # ExSlop: 31 default AI-slop checks. ExDNA.Credo: clone diagnostics inline.
      plugins: [{ExSlop, []}],
      checks: [
        # AST clone detection surfaced as Credo issues
        {ExDNA.Credo, []},

        # Increase cyclomatic complexity threshold from 9 to 11
        # This accommodates legitimate complexity in:
        # - config.ex validation (10)
        # - client.ex routing and message handling (10)
        # - error_handler.ex comprehensive categorization (19 - still warned)
        {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 11},
        
        # Increase nesting depth for test files which need deeper nesting
        # for comprehensive integration testing scenarios
        {Credo.Check.Refactor.Nesting, max_nesting: 3, files: %{included: ["test/"]}},
        
        # Keep default nesting for lib files
        {Credo.Check.Refactor.Nesting, max_nesting: 2, files: %{included: ["lib/"]}}
      ]
    }
  ]
}