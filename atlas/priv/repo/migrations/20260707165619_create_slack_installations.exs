defmodule Atlas.Repo.Migrations.CreateSlackInstallations do
  use Ecto.Migration

  def change do
    create table(:slack_installations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :app_key, :string, null: false
      add :team_id, :string, null: false
      add :team_name, :string
      add :bot_user_id, :string
      add :bot_token, :bytea
      add :scope, :text
      add :installed_at, :utc_datetime
      add :disconnected_at, :utc_datetime
      add :installed_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:slack_installations, [:team_id])
    create unique_index(:slack_installations, [:app_key])
    create index(:slack_installations, [:installed_by_user_id])
  end
end
