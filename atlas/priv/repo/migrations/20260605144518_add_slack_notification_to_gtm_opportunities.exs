defmodule Atlas.Repo.Migrations.AddSlackNotificationToGtmOpportunities do
  use Ecto.Migration

  def change do
    alter table(:gtm_opportunities) do
      add :slack_notification_channel_id, :string
      add :slack_notification_thread_ts, :string
      add :slack_notification_posted_at, :utc_datetime
    end

    create index(:gtm_opportunities, [:slack_notification_thread_ts])
  end
end
