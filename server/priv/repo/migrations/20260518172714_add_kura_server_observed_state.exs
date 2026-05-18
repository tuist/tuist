defmodule Tuist.Repo.Migrations.AddKuraServerObservedState do
  use Ecto.Migration

  # Observed-state snapshot for Kura servers. `status` is no longer an
  # independently-mutated state machine; the reconciler projects it from
  # the backing KuraInstance every tick. These columns make the
  # observation that drives the projection durable and queryable
  # (operator UI, drift, audit) instead of recomputed-and-discarded.
  #
  # Nullable and backfilled by the reconciler on the next ticks, so the
  # add is safe on a live table.
  def up do
    alter table(:kura_servers) do
      add :observed_image_tag, :string
      add :observed_ready_at, :timestamptz
      add :last_observed_at, :timestamptz
    end
  end

  def down do
    alter table(:kura_servers) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :observed_image_tag, :string
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :observed_ready_at, :timestamptz
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :last_observed_at, :timestamptz
    end
  end
end
