defmodule Tuist.Tests.TestRunTrackedFile do
  @moduledoc """
  One tracked file as a test run saw it: a file the project's tracked-file
  globs match (dependency manifests, generator configuration, fixtures,
  snapshots; see `Tuist.GitHistory.settings/1`) with the Git blob it had at
  the run's commit. A run's evidence may only be reused by a later run when
  every tracked file is identical, so the snapshot is recorded from the
  first run on. `test_runs.tracked_files_truncated` says the client stopped
  at the limit. Stored in ClickHouse, keyed by run.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @primary_key false
  schema "test_run_tracked_files" do
    field :project_id, Ch, type: "Int64"
    field :test_run_id, Ecto.UUID
    field :path, Ch, type: "String"
    field :git_blob_id, Ch, type: "String", default: ""
    field :inserted_at, Ch, type: "DateTime64(6)"
  end
end
