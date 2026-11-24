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
          # Phoenix-shaped code (transactional state machines in
          # Approvals.approve) routinely sits at 3 levels of nesting;
          # matches slack's loosened threshold.
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          # Approvals.approve/2 is a single Repo.transaction state
          # machine with cond branches per request status + per
          # gate (self-approve / approver-allowed / expired / etc.).
          # Splitting it would obscure the linear transitional shape;
          # bump the limit instead.
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 20]}
        ],
        disabled: [
          {Credo.Check.Design.TagTODO, []},
          {Credo.Check.Readability.ModuleDoc, []}
        ]
      }
    }
  ]
}
