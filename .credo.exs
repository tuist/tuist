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
      checks: [
        {Credo.Checks.TimestampsType,
         files: %{included: ["priv/repo/migrations/"]}, allowed_type: :timestamptz},
        {Credo.Checks.TimestampsType, files: %{included: ["lib/"]}, allowed_type: :utc_datetime}
      ]
    }
  ]
}
