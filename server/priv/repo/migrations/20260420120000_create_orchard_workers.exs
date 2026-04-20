defmodule Tuist.Repo.Migrations.CreateOrchardWorkers do
  use Ecto.Migration

  def change do
    create_query =
      "CREATE TYPE orchard_worker_status AS ENUM ('queued', 'provisioning', 'online', 'draining', 'terminating', 'terminated', 'failed')"

    drop_query = "DROP TYPE orchard_worker_status"
    execute(create_query, drop_query)

    create table(:orchard_workers, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :string, null: false
      add :status, :orchard_worker_status, default: "queued", null: false
      add :scaleway_server_id, :string
      add :scaleway_zone, :string, null: false
      add :scaleway_server_type, :string, null: false
      add :scaleway_os, :string, null: false
      add :ip_address, :string
      add :error_message, :text
      add :last_seen_at, :timestamptz
      add :provisioned_at, :timestamptz
      add :terminated_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create unique_index(:orchard_workers, [:name])
    create unique_index(:orchard_workers, [:scaleway_server_id])
    create index(:orchard_workers, [:status])
  end
end
