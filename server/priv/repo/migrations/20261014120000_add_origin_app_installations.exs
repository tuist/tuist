defmodule Tuist.Repo.Migrations.AddOriginAppInstallations do
  use Ecto.Migration

  def change do
    create table(:origin_app_installations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :installation_id, :text, null: false
      add :app_id, :text, null: false
      add :namespace_id, :text, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:origin_app_installations, [:app_id, :installation_id])
    create index(:origin_app_installations, [:account_id])

    alter table(:vcs_connections) do
      modify :github_app_installation_id, :uuid, null: true, from: {:uuid, null: false}

      add :origin_app_installation_id,
          references(:origin_app_installations, type: :uuid, on_delete: :delete_all)
    end

    create index(:vcs_connections, [:origin_app_installation_id])

    create constraint(:vcs_connections, :vcs_connections_provider_installation,
             check:
               "(provider = 0 AND github_app_installation_id IS NOT NULL AND origin_app_installation_id IS NULL) OR (provider = 1 AND origin_app_installation_id IS NOT NULL AND github_app_installation_id IS NULL)"
           )
  end
end
