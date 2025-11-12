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
      requires: ["./credo/checks/**/*.ex"],
      checks: %{
        enabled: [{Credo.Check.Refactor.Nesting, [max_nesting: 3]}],
        extra: [
          {TimestampsType, files: %{included: ["priv/repo/migrations/"]}, allowed_type: :timestamptz},
          {TimestampsType, files: %{included: ["lib/"]}, allowed_type: :utc_datetime},
          {ExcellentMigrations.CredoCheck.MigrationsSafety, []}
        ],
        disabled: [
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
