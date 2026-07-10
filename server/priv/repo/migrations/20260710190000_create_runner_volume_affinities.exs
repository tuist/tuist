defmodule Tuist.Repo.Migrations.CreateRunnerVolumeAffinities do
  use Ecto.Migration

  # Dispatch-time volume affinity (spec #76). One row per
  # (node_name, account_id, volume_name) recording when a job of that
  # account last ran on that Mac host. It is the "this host recently ran
  # this account, so it likely holds its cache volume" signal: dispatch
  # prefers an affine account's queued job (within a bounded age
  # tolerance) for a polling runner on that node, so jobs land on hosts
  # that already hold the account's warm volume.
  #
  # Disposable by construction — a stale row only costs the status-quo
  # cold path, which also re-warms the volume — so rows are pruned after
  # 14 days (past any plausible volume lifetime under LRU). Named from day
  # one (`volume_name`, tuist-cache reserved) so generic volumes (spec
  # #69) are new names, not a re-keying migration.
  def change do
    create table(:runner_volume_affinities) do
      add :node_name, :string, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :volume_name, :string, null: false, default: "tuist-cache"
      add :last_run_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    # Upsert key: at most one row per (host, account, volume). The claim
    # flow bumps last_run_at on this conflict target.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_volume_affinities, [:node_name, :account_id, :volume_name])

    # Affine-accounts-for-this-node lookup on the dispatch hot path.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_volume_affinities, [:node_name, :volume_name])

    # Prune scan: delete rows whose last_run_at is older than the
    # retention window.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_volume_affinities, [:last_run_at])
  end
end
