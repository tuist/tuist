defmodule Tuist.Tests.TestSelectionTest do
  @moduledoc """
  A test a selection run (`Tuist.Tests.TestSelectionRun`) requested and what
  it decided: `selected`, on the shard `shard_index`, or `skipped` (shard
  `0`, unused). `reason` says why (`impacted`, `target_changed`,
  `failed_at_baseline`, `no_evidence` or `run_all` when selected;
  `unaffected` when skipped), `matched_path` the changed path behind
  `impacted` and `target_changed`, and `estimated_duration_ms` the duration
  the shards were packed by. The selected rows are the shard plan; the
  outcome is in `test_case_runs`. This is a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_selection_tests" do
    field :project_id, Ch, type: "Int64"
    field :selection_run_id, Ch, type: "UUID"
    field :test_case_id, Ch, type: "UUID"
    field :module_name, Ch, type: "String"
    field :suite_name, Ch, type: "String"
    field :name, Ch, type: "String"
    field :decision, Ch, type: "LowCardinality(String)"
    field :shard_index, Ch, type: "UInt16"
    field :reason, Ch, type: "LowCardinality(String)"
    field :matched_path, Ch, type: "String"
    field :estimated_duration_ms, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
