defmodule Tuist.Tests.TestCaseRunHash do
  @moduledoc """
  Records a single test case run's outcome under the selective-testing hash
  of its module. Backs hash-based cross-run flakiness detection: a test case
  that runs at the same `selective_testing_hash` (so nothing affecting that
  module changed, even across commits) but produces a different status than a
  previous CI run is flaky.

  Written by `Tuist.Tests.detect_flaky_tests_by_hash/2` off command-event
  ingestion, because the hash only becomes known once the command event lands
  on `xcode_targets` (after the `test_case_runs` themselves are ingested).

  Ordered by `(project_id, selective_testing_hash, is_ci, scheme,
  test_case_id, test_case_run_id)` so the lookup keyed on project + hash +
  CI + scheme reads a small contiguous range. `test_case_run_id` is the
  `test_case_runs.id` of the underlying run, so the caller can re-fetch the
  full row to mark it flaky.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "test_case_run_hashes" do
    field :project_id, Ch, type: "Int64"
    field :selective_testing_hash, Ch, type: "String"
    field :scheme, Ch, type: "String"
    field :test_case_id, Ch, type: "UUID"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :is_ci, :boolean, default: false
    field :test_case_run_id, Ch, type: "UUID"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
