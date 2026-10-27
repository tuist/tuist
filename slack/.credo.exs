%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "priv/repo/migrations/",
          "test/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      checks: %{
        extra: [
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]}
        ],
        disabled: [
          {Credo.Check.Design.TagTODO, []},
          {Credo.Check.Readability.ModuleDoc, []}
        ]
      }
    }
  ]
}
