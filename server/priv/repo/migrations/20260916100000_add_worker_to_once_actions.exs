defmodule Tuist.Repo.Migrations.AddWorkerToOnceActions do
  use Ecto.Migration

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
