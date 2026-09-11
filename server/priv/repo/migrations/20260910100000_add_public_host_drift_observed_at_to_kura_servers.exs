defmodule Tuist.Repo.Migrations.AddPublicHostDriftObservedAtToKuraServers do
  use Ecto.Migration

  # Clock the reconciler holds the endpoint probe on while a server's rendered
  # public host differs from its stored url, so the probe cannot resolve the new
  # host ahead of its DNS record. Nullable and written only while such a change
  # is outstanding, so the add is safe on a live table.
  def up do
    alter table(:kura_servers) do
      add :public_host_drift_observed_at, :timestamptz
    end
  end

  def down do
    alter table(:kura_servers) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove_if_exists :public_host_drift_observed_at, :timestamptz
    end
  end
end
