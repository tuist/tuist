defmodule Tuist.Repo.Migrations.CreateKuraTables do
  @moduledoc """
  Kura servers are one provisioned Kura mesh for a single account in a
  single region. Deployments track each install/update attempt for a
  server.

  The active server identity is `(account_id, region)`. The unique
  index excludes destroyed rows so a replacement can be created after
  teardown.
  """
  use Ecto.Migration

  @destroyed_status 4

  def change do
    create table(:kura_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      add :region, :string, null: false
      add :spec, :integer, null: false, default: 1
      add :volume_size_gi, :integer, null: false
      add :status, :integer, null: false, default: 0
      add :url, :string
      add :current_image_tag, :string
      add :provisioner_node_ref, :string, null: false

      timestamps(type: :timestamptz)
    end

    create constraint(:kura_servers, :kura_servers_spec_valid, check: "spec IN (0, 1, 2)")

    create constraint(:kura_servers, :kura_servers_status_valid,
             check: "status IN (0, 1, 2, 3, 4)"
           )

    create index(:kura_servers, [:account_id])

    create unique_index(
             :kura_servers,
             [:account_id, :region],
             name: :kura_servers_account_region_active_index,
             where: "status <> #{@destroyed_status}"
           )

    create table(:kura_deployments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :cluster_id, :string, null: false
      add :image_tag, :string, null: false
      add :status, :integer, null: false, default: 0

      add :kura_server_id,
          references(:kura_servers, type: :binary_id, on_delete: :delete_all),
          null: false

      add :error_message, :text
      add :oban_job_id, :bigint
      add :started_at, :timestamptz
      add :finished_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create constraint(:kura_deployments, :kura_deployments_status_valid,
             check: "status IN (0, 1, 2, 3, 4)"
           )

    create index(:kura_deployments, [:kura_server_id, :inserted_at])
  end
end
