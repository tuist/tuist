defmodule Tuist.IngestRepo.Migrations.AddOnceRunIdToTestRuns do
  use Ecto.Migration

  # The Once counterpart of `bazel_invocation_id`: links a shared test run
  # back to the `once_runs` row whose streamed events produced it.
  def change do
    alter table(:test_runs) do
      add :once_run_id, :string, default: ""
    end
  end
end
