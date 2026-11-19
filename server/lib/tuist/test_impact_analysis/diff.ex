defmodule Tuist.TestImpactAnalysis.Diff do
  @moduledoc """
  The files that changed between a baseline and the commit that was checked
  out, as the client's diff listed them: path, status, blob (empty for deleted
  files) and the test modules each can affect. At most 5,000 files are kept;
  `changed_files_count` is the diff's total size. A diff is deterministic, so
  one per checked-out commit and baseline is reused by every invocation on that
  commit. This is a ClickHouse entity.
  """
  use Ecto.Schema

  @primary_key false
  schema "test_impact_diffs" do
    field :project_id, Ch, type: "Int64"
    field :commit_sha, Ch, type: "String"
    field :baseline_sha, Ch, type: "String"
    field :changed_files, Ch, type: "Array(Tuple(String, LowCardinality(String), String, Array(String)))", default: []
    field :changed_files_count, Ch, type: "UInt32", default: 0
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
