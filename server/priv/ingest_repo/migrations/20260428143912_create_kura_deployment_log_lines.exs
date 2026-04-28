defmodule Tuist.IngestRepo.Migrations.CreateKuraDeploymentLogLines do
  use Ecto.Migration

  # Per-line log output for a Kura deployment. Written by the rollout
  # Oban worker as it streams stdout/stderr from `helm` and the wrapping
  # rollout script. The Postgres `kura_deployments` row owns the
  # deployment metadata; this table is the high-volume append-only
  # backing store for the live log tail in the /ops UI.
  def change do
    create table(:kura_deployment_log_lines,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (deployment_id, sequence)"
           ) do
      add :deployment_id, :uuid, null: false
      add :sequence, :UInt64, null: false
      add :stream, :"Enum8('stdout' = 0, 'stderr' = 1)", null: false
      add :line, :string, null: false
      add :inserted_at, :timestamp, default: fragment("now64(3)")
    end
  end
end
