defmodule Atlas.Repo.Migrations.CreateErrorSummarySettings do
  use Ecto.Migration

  def change do
    create table(:error_summary_settings, primary_key: false) do
      add :id, :text, primary_key: true
      add :enabled, :boolean, null: false, default: false
      add :schedule, :string, null: false, default: "0 9 * * *"
      add :slack_channel_id, :string

      timestamps(type: :timestamptz)
    end
  end
end
