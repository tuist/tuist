defmodule Tuist.Repo.Migrations.CreateRunnerVolumeHeads do
  use Ecto.Migration

  # The canonical current version of each account's cache volume. One row per
  # (account_id, volume_name): a monotonic generation plus the inventory digest
  # of the account's current warm set, published by whichever host most
  # recently promoted a successful, cache-changing job for that account.
  #
  # A host's on-disk master drifts — it only holds what that account last ran
  # on that host — and hosts re-converge lazily through the content-addressed
  # remote. The HEAD gives every host one reference point to converge toward,
  # so a job materializes a near-current warm set instead of this host's stale
  # subset. Last-writer-wins, matching the volume's own promote semantics; a
  # stale HEAD only costs a status-quo cold-ish job. Cascade-deleted with the
  # account, so no separate prune is needed.
  def change do
    create table(:runner_volume_heads) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :volume_name, :string, null: false, default: "tuist-cache"
      add :generation, :bigint, null: false, default: 0
      add :tree_digest, :string
      add :node_name, :string

      timestamps(type: :timestamptz)
    end

    # Upsert key: at most one HEAD per (account, volume). The promote report
    # bumps generation + digest on this conflict target.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_volume_heads, [:account_id, :volume_name])
  end
end
