defmodule Atlas.Repo.Migrations.AddOutreachCandidateSlackNotifications do
  use Ecto.Migration

  def change do
    alter table(:outreach_candidates) do
      add :slack_notification_requested_at, :utc_datetime
      add :slack_notification_posted_at, :utc_datetime
      add :slack_notification_channel_id, :string
      add :slack_notification_thread_ts, :string
    end

    create index(:outreach_candidates, [:slack_notification_requested_at],
             where:
               "slack_notification_requested_at IS NOT NULL AND slack_notification_posted_at IS NULL",
             name: :outreach_candidates_pending_slack_notification_index
           )
  end
end
