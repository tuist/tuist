defmodule Tuist.Repo.Migrations.CreateKuraServers do
  use Ecto.Migration

  def change do
    create table(:kura_servers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id,
          references(:accounts, on_delete: :delete_all),
          null: false

      add :cluster_id, :string, null: false
      add :spec, :integer, null: false, default: 1
      add :volume_size_gi, :integer, null: false
      add :status, :integer, null: false, default: 0
      add :url, :string
      add :current_image_tag, :string
      add :requested_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create index(:kura_servers, [:account_id])
    create index(:kura_servers, [:status])
    create unique_index(:kura_servers, [:account_id, :cluster_id, :spec])

    alter table(:kura_deployments) do
      add :kura_server_id, references(:kura_servers, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:kura_deployments, [:kura_server_id])
  end
end
