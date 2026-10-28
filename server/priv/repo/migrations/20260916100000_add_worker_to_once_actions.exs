defmodule Tuist.Repo.Migrations.AddWorkerToOnceActions do
  use Ecto.Migration

  # Every table this migration touches (once_runs, once_actions,
  # once_cache_events, once_system_samples, once_test_suite_runs,
  # once_test_case_runs) is introduced by this same unreleased change, so
  # the first time this runs there is no populated table to lock and no
  # concurrent reader to block.
  # excellent_migrations:safety-assured-for-this-file column_added_with_default
  # excellent_migrations:safety-assured-for-this-file column_type_changed
  # excellent_migrations:safety-assured-for-this-file index_not_concurrently

  @moduledoc """
  Store the tokio worker that ran each action so the Timeline tab can
  render one flame-graph row per worker, matching Bazel's per-`tid`
  grouping. Also relax the timestamp columns to microsecond precision
  so 1000 actions completing in the same second don't collapse into
  one flame-graph slice.
  """

  def change do
    alter table(:once_actions) do
      add :worker_id, :string, size: 64, default: "", null: false
      modify :started_at, :timestamptz, from: :timestamptz, null: true
      modify :finished_at, :timestamptz, from: :timestamptz
    end

    create index(:once_actions, [:once_run_id, :worker_id])
  end
end
