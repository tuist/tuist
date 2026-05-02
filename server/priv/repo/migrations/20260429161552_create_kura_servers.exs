defmodule Tuist.Repo.Migrations.CreateKuraServers do
  @moduledoc """
  A `kura_server` is one Kura mesh provisioned for a single account in
  a single region. Identity is `(account_id, region)`: an account can
  light up Kura in as many regions as it needs, but only one mesh per
  region.

  `provisioner_node_ref` is the opaque handle the region's provisioner
  returns from `provision/3`. The control plane stores it untouched.

  The unique index is partial on `status != :destroyed` so a
  destroyed row never blocks a fresh provision against the same
  `(account, region)`.
  """
  use Ecto.Migration

  # Numeric value of `KuraServer` status `:destroyed`. Hard-coded
  # rather than referencing the enum so this migration is
  # self-contained.
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

    create index(:kura_servers, [:account_id])

    create unique_index(
             :kura_servers,
             [:account_id, :region],
             name: :kura_servers_account_region_active_index,
             where: "status <> #{@destroyed_status}"
           )

    alter table(:kura_deployments) do
      add :kura_server_id,
          references(:kura_servers, type: :binary_id, on_delete: :delete_all),
          null: false
    end

    create index(:kura_deployments, [:kura_server_id, :inserted_at])
  end
end
