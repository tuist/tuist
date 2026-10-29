defmodule Tuist.IngestRepo.Migrations.AddBazelInvocationIdToTestRuns do
  use Ecto.Migration

  def change do
    alter table(:test_runs) do
      add :bazel_invocation_id, :string, default: ""
    end
  end
end
