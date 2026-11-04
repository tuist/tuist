defmodule TuistWeb.API.Schemas.Tests.TestImpact.Baseline do
  @moduledoc """
  The baseline coverage-based test selection diffs the checked-out commit
  against, or the reason there's none.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "TestImpactBaseline",
    type: :object,
    description:
      "The nearest ancestor of the checked-out commit with a full run on the same platform, within 20 commits with coverage, or the reason there's none.",
    properties: %{
      baseline_sha: %Schema{
        type: :string,
        nullable: true,
        description: "The baseline commit. Null when there's none, and `reason` says why."
      },
      reason: %Schema{
        type: :string,
        description:
          "Why there's no baseline: `history_unknown`, `no_baseline`, `baseline_too_old`, `no_baseline_evidence`, `excluded_branch`, or `not_enabled`. `excluded_branch` means the request's `git_branch` is the project's default branch, which never selects: the client runs every test in scope. `history_unknown` means the server's history has none of the checked-out commit, the parents and the ancestors sent: the client deepens its checkout once by 100 commits and repeats the request with `ancestor_shas`. After `not_enabled` the client runs default selective testing and makes no further selection call; after any other reason it still creates the impact run, with the reason as `fallback_reason`. A plain string so new reasons don't break older clients, which treat an unknown reason like `not_enabled`."
      },
      diff_cached: %Schema{
        type: :boolean,
        description:
          "Whether the diff between the checked-out commit and the baseline is already stored. When true and the checkout is clean, the client skips deepening and diffing and sends no `changed_files`."
      }
    }
  })
end
