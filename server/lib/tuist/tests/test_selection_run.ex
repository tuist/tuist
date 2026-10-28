defmodule Tuist.Tests.TestSelectionRun do
  @moduledoc """
  One invocation's test selection: the scope it requested (scheme or test
  plan, destination, targets), the test impact it applied (`baseline_sha`,
  empty when it fell back to running everything, with `fallback_reason`),
  its `mode` (`dry_run` or `enabled`), how it was sharded, the CI run and
  job that asked for it (`idempotency_key`), and the counts. `test_run_id`
  is the test run that reported its results; `missed_count` the tests it
  would have skipped that failed, recorded once that run is processed.
  `skipped_duration` is the skipped tests' estimated duration, in
  milliseconds. This is a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_selection_runs" do
    field :project_id, Ch, type: "Int64"
    field :idempotency_key, Ch, type: "String"
    field :git_commit_sha, Ch, type: "String"
    field :git_branch, Ch, type: "String"
    field :baseline_sha, Ch, type: "String"
    field :scheme, Ch, type: "String"
    field :test_plan, Ch, type: "String"
    field :destination, Ch, type: "String"
    field :requested_targets, Ch, type: "Array(String)"
    field :mode, Ch, type: "LowCardinality(String)"
    field :shard_count, Ch, type: "UInt16"
    field :shard_plan_id, Ch, type: "Nullable(UUID)"
    field :test_run_id, Ch, type: "Nullable(UUID)"
    field :ci_provider, Ch, type: "LowCardinality(String)"
    field :ci_run_id, Ch, type: "String"
    field :ci_job_id, Ch, type: "String"
    field :requested_count, Ch, type: "UInt32"
    field :selected_count, Ch, type: "UInt32"
    field :skipped_count, Ch, type: "UInt32"
    field :missed_count, Ch, type: "UInt32"
    field :skipped_duration, Ch, type: "UInt64"
    field :fallback_reason, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :updated_at, Ch, type: "DateTime64(6)"
  end
end
