alias Credo.Checks.DisallowSpec
alias Credo.Checks.TimestampsType

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
      requires: [
        "./credo/checks/**/*.ex",
        "../tuist_common/credo/checks/**/*.ex"
      ],
      checks: %{
        extra: [
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          {TimestampsType, files: %{included: ["priv/repo/migrations/"]}, allowed_type: :timestamptz},
          {TimestampsType, files: %{included: ["lib/"]}, allowed_type: :utc_datetime},
          {DisallowSpec, []},
          {ExcellentMigrations.CredoCheck.MigrationsSafety, []},
          {Credo.Checks.UnusedReturnValue, files: %{excluded: ["priv/repo/migrations/"]}}
        ],
        disabled: [
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
