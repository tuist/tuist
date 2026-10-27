defmodule Tuist.Repo.Migrations.CreateOnceSystemSamples do
  use Ecto.Migration

  # Every table this migration touches (once_runs, once_actions,
  # once_cache_events, once_system_samples, once_test_suite_runs,
  # once_test_case_runs) is introduced by this same unreleased change, so
  # the first time this runs there is no populated table to lock and no
  # concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file index_not_concurrently

  @moduledoc """
  Storage for `once.events.v1` SystemSampled events: one row per
  sample, published at 1 Hz from the Once client while a run runs.
  Feeds the CPU / Memory / Network In / Network Out charts on the
  Once run's Timeline tab.
  """

  def change do
    create table(:once_system_samples, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :once_run_id, references(:once_runs, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, :string, null: false, size: 128
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      # Wall-clock instant the client observed the sample at.
      add :at_ms, :bigint, null: false

      # Whole-host CPU utilisation in [0.0, 100.0]. Averaged across
      # cores so a 4-core machine at full load reports 100.
      add :cpu_percent, :float, null: false, default: 0.0

      # Whole-host memory usage in bytes, matching `used_memory`.
      add :memory_bytes, :bigint, null: false, default: 0

      # Cumulative bytes moved by all network interfaces at sample
      # time; the LiveView takes the sample-to-sample delta to render
      # bytes-per-second.
      add :network_in_bytes, :bigint, null: false, default: 0
      add :network_out_bytes, :bigint, null: false, default: 0

      add :observed_at, :timestamptz, null: false
    end

    create index(:once_system_samples, [:once_run_id, :at_ms])
    create index(:once_system_samples, [:project_id, :observed_at])
  end
end
