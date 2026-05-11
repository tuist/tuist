defmodule Tuist.Tests.TestCaseRunByCommit do
  @moduledoc """
  Slim read-only schema backed by the `test_case_runs_by_commit`
  materialized view. Ordered by
  `(project_id, git_commit_sha, scheme, is_ci, status, id)`, making the
  cross-run flakiness lookup (filter by project + commit + scheme + CI +
  status) efficient.

  `scheme` is part of the key so two runs on the same commit but different
  schemes are treated as separate execution variants and do not flag each
  other as flaky (a same-commit pass on one scheme does not contradict a
  same-commit fail on another).

  The previous (no-scheme) table was atomically swapped into
  `test_case_runs_by_commit_v2` by the migration that introduced the new
  schema; the legacy table is dropped in a follow-up migration once the
  rollout is stable.

  Used by `Tuist.Tests.get_existing_ci_runs_for_commit/4` to identify
  historical CI runs for a given commit and scheme; the main table is then
  hit by `id` (via the `idx_id` bloom filter) only for the small subset that
  needs full rows.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_runs_by_commit" do
    field :project_id, Ch, type: "Int64"
    field :git_commit_sha, Ch, type: "String"
    field :scheme, Ch, type: "String"
    field :is_ci, :boolean, default: false
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :test_case_id, Ch, type: "Nullable(UUID)"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
