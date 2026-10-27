defmodule Tuist.IngestRepo.Migrations.CreateBuildMachineMetricsTable do
  use Ecto.Migration

  def change do
    create table(:build_machine_metrics,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (inserted_at, timestamp) TTL inserted_at + INTERVAL 90 DAY"
           ) do
      add :build_run_id, :"Nullable(UUID)"
      add :gradle_build_id, :"Nullable(UUID)"
      add :timestamp, :Float64, null: false
      add :cpu_usage_percent, :Float32, null: false
      add :memory_used_bytes, :Int64, null: false
      add :memory_total_bytes, :Int64, null: false
      add :network_bytes_in, :Int64, null: false
      add :network_bytes_out, :Int64, null: false
      add :disk_bytes_read, :Int64, null: false
      add :disk_bytes_written, :Int64, null: false
      add :inserted_at, :naive_datetime, null: false, default: fragment("now()")
    end
  end
end
