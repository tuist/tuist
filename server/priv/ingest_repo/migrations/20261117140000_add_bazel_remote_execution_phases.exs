defmodule Tuist.IngestRepo.Migrations.AddBazelRemoteExecutionPhases do
  use Ecto.Migration

  def change do
    alter table(:bazel_profile_steps) do
      add :remote_queue_ms, :"Nullable(Float64)"
      add :remote_input_fetch_ms, :"Nullable(Float64)"
      add :remote_execution_ms, :"Nullable(Float64)"
      add :remote_output_upload_ms, :"Nullable(Float64)"
    end
  end
end
