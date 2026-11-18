%{
  configs: [
    %{
      name: "default",
      requires: [
        "./credo/checks/no_nested_modules.ex",
        "./credo/checks/no_typespecs.ex",
        "./credo/checks/no_rescue.ex"
      ],
      checks: %{
        extra: [
          {Condukt.Credo.Check.Readability.NoNestedModules, []},
          {Condukt.Credo.Check.Readability.NoTypespecs, []},
          {Condukt.Credo.Check.Readability.NoRescue, []}
        ]
      }
    }
  ]
}
