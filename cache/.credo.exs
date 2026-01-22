alias Credo.Checks.{DisallowSpec, TimestampsType}

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
      requires: ["../tuist_common/credo/checks/**/*.ex"],
      checks: %{
        extra: [
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          {TimestampsType, files: %{included: ["lib/"]}, allowed_type: :utc_datetime},
          {DisallowSpec, []},
          {Credo.Checks.UnusedReturnValue,
           [
             files: %{excluded: ["priv/repo/migrations/"]},
             modules: [[:Cache, :Repo], [:Repo], [:Oban]]
           ]}
        ],
        disabled: [
          {Credo.Check.Design.TagTODO, []}
        ]
      }
    }
  ]
}
