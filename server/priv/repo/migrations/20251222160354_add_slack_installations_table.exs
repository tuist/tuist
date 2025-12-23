defmodule Tuist.Repo.Migrations.AddSlackInstallationsTable do
  use Ecto.Migration

  def change do
    create table(:slack_installations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :team_id, :string, null: false
      add :team_name, :string
      add :access_token, :binary, null: false
      add :bot_user_id, :string

      timestamps(type: :timestamptz)
    end

    create unique_index(:slack_installations, [:account_id])
    create unique_index(:slack_installations, [:team_id])
  end
end
