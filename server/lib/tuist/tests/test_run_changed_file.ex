defmodule Tuist.Tests.TestRunChangedFile do
  @moduledoc """
  One file a test run's commit changed against its merge base, as the client
  saw it (`git diff` between the two). `status` is `added`, `modified`,
  `deleted` or `renamed` (with `previous_path`); `hunk_starts` and
  `hunk_ends` are the changed line ranges in the file at the head, index by
  index, and `git_blob_id` the file's blob at the head (empty for a deleted
  file). `truncated` says the client stopped listing hunks for the file
  because the diff exceeded its limits.

  Patch coverage joins these ranges with the run's `coverage_files` rows.
  Stored in ClickHouse, keyed by run.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "test_run_changed_files" do
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ecto.UUID
    field :path, Ch, type: "String"
    field :previous_path, Ch, type: "String", default: ""
    field :status, Ch, type: "LowCardinality(String)"
    field :git_blob_id, Ch, type: "String", default: ""
    field :hunk_starts, Ch, type: "Array(UInt32)"
    field :hunk_ends, Ch, type: "Array(UInt32)"
    field :truncated, :boolean, default: false
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
