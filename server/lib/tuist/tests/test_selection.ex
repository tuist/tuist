defmodule Tuist.Tests.TestSelection do
  @moduledoc """
  A commit's test selection plan (`Tuist.Tests.Selections`): which tests or
  test targets its runs had to execute and which they could skip, decided
  against the per-test coverage evidence of the nearest full run, the
  baseline. `scope` says what the plan decided on (`test` or `target`),
  `mode` whether the skips were applied (`enabled`) or only reported
  (`dry_run`), and `fallback_reason` why every test was selected, when one
  was. `skipped_duration` is how long, in milliseconds, the skipped tests
  took in the baseline. This is a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_selections" do
    field :project_id, Ch, type: "Int64"
    field :git_commit_sha, Ch, type: "String"
    field :git_branch, Ch, type: "String"
    field :scope, Ch, type: "LowCardinality(String)"
    field :mode, Ch, type: "LowCardinality(String)"
    field :baseline_commit_sha, Ch, type: "String"
    field :fallback_reason, Ch, type: "LowCardinality(String)"
    field :selected_count, Ch, type: "UInt32"
    field :skipped_count, Ch, type: "UInt32"
    field :changed_files_count, Ch, type: "UInt32"
    field :skipped_duration, Ch, type: "UInt64"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
