defmodule Tuist.Repo.Migrations.RemoveBuiltinRunnerCacheVolumes do
  @moduledoc """
  Removes the built-in macOS runner cache volume's data: its HEAD and orphan
  rows (volume names other than `macos-` and `linux-` custom storage names), its
  inventory rows in `runner_cache_volumes` (uses and measurements cascade), and
  the unused `runner_volume_affinities` table. It first queues
  `Tuist.Runners.Workers.PurgeBuiltinVolumeMastersWorker` for every account that
  may hold built-in master objects in storage, naming the worker by string.
  """
  use Ecto.Migration

  import Ecto.Query

  @cleanup_statements [
    "DELETE FROM runner_volume_heads WHERE volume_name NOT LIKE 'macos-%' AND volume_name NOT LIKE 'linux-%'",
    "DELETE FROM runner_volume_master_orphans WHERE volume_name NOT LIKE 'macos-%' AND volume_name NOT LIKE 'linux-%'",
    "DELETE FROM runner_cache_volumes WHERE builtin_name IS NOT NULL"
  ]

  def up do
    enqueue_purges!(repo())

    for statement <- cleanup_statements() do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute(statement)
    end

    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop_if_exists table(:runner_volume_affinities)
  end

  def cleanup_statements, do: @cleanup_statements

  def enqueue_purges!(repo) do
    now = NaiveDateTime.utc_now()

    account_ids()
    |> repo.all()
    |> Enum.uniq()
    |> Enum.map(fn account_id ->
      %{
        state: "available",
        queue: "default",
        worker: "Tuist.Runners.Workers.PurgeBuiltinVolumeMastersWorker",
        args: %{account_id: account_id},
        max_attempts: 20,
        inserted_at: now,
        scheduled_at: now
      }
    end)
    |> Enum.chunk_every(1000)
    |> Enum.each(&repo.insert_all("oban_jobs", &1))
  end

  def down do
    create_if_not_exists table(:runner_volume_affinities) do
      add :node_name, :string, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :volume_name, :string, null: false, default: "tuist-cache"
      add :last_run_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create_if_not_exists unique_index(:runner_volume_affinities, [
                           :node_name,
                           :account_id,
                           :volume_name
                         ])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create_if_not_exists index(:runner_volume_affinities, [:node_name, :volume_name])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create_if_not_exists index(:runner_volume_affinities, [:last_run_at])
  end

  defp account_ids do
    builtin_heads =
      from(h in "runner_volume_heads",
        where: not like(h.volume_name, "macos-%") and not like(h.volume_name, "linux-%"),
        select: h.account_id
      )

    builtin_orphans =
      from(o in "runner_volume_master_orphans",
        where: not like(o.volume_name, "macos-%") and not like(o.volume_name, "linux-%"),
        select: o.account_id
      )

    builtin_volumes =
      from(v in "runner_cache_volumes", where: not is_nil(v.builtin_name), select: v.account_id)

    affinities = from(a in "runner_volume_affinities", select: a.account_id)

    macos_sessions =
      from(s in "runner_sessions", where: s.platform == "macos", select: s.account_id)

    builtin_heads
    |> union(^builtin_orphans)
    |> union(^builtin_volumes)
    |> union(^affinities)
    |> union(^macos_sessions)
  end
end
