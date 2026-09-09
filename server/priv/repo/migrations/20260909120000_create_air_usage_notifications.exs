defmodule Tuist.Repo.Migrations.CreateAirUsageNotifications do
  use Ecto.Migration

  def change do
    create table(:air_usage_notifications) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :period_start, :timestamptz, null: false
      add :threshold, :integer, null: false
      add :usage, :integer, null: false
      add :limit, :integer, null: false
      add :delivered_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(
             :air_usage_notifications,
             [:account_id, :user_id, :period_start, :threshold],
             name: :air_usage_notifications_recipient_threshold_index
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:air_usage_notifications, [:user_id])
  end
end
