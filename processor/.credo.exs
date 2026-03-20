alias Credo.Checks.DisallowDirectivesInFunction
alias Credo.Checks.DisallowGlobalStateMutation
alias Credo.Checks.DisallowSpec

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      requires: ["../tuist_common/credo/checks/**/*.ex"],
      checks: %{
        extra: [
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          {DisallowSpec, []},
          {DisallowDirectivesInFunction, files: %{included: ["lib/"]}},
          {DisallowGlobalStateMutation, files: %{included: ["test/"]}}
        ],
        disabled: [
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
