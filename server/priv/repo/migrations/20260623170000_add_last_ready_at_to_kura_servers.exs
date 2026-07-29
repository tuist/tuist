defmodule Tuist.Repo.Migrations.AddLastReadyAtToKuraServers do
  use Ecto.Migration

  # Readiness heartbeat for Kura servers. The reconciler stamps this each
  # tick a private node-port server's endpoint is observable (the backing
  # KuraInstance only publishes the endpoint for a ready primary pod), so
  # `runner_cache_endpoint_url/2` can fail dispatch over to the public
  # cache once the heartbeat goes stale instead of routing builds at a
  # `/ready`-503 node. Distinct from `last_observed_at`, which tracks the
  # last successful image observation regardless of endpoint readiness.
  #
  # Nullable and stamped by the reconciler on the next ticks, so the add
  # is safe on a live table.
  def up do
    alter table(:kura_servers) do
      add :last_ready_at, :timestamptz
    end
  end

  def down do
    alter table(:kura_servers) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :last_ready_at, :timestamptz
    end
  end
end
