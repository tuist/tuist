defmodule Atlas.Repo.Migrations.CreateOutreachRecommendations do
  use Ecto.Migration

  def change do
    alter table(:account_contacts) do
      add :outreach_recommendations_checked_at, :utc_datetime
    end

    create table(:outreach_recommendations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :contact_id, references(:account_contacts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source_event_id, references(:account_events, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending"
      add :action_type, :string, null: false
      add :recommended_event_kind, :string
      add :title, :string, null: false
      add :guidance, :text, null: false
      add :rationale, :text, null: false
      add :draft_message, :text
      add :due_at, :utc_datetime, null: false
      add :confidence, :decimal, precision: 5, scale: 4, null: false
      add :evidence, :map, null: false, default: %{"items" => []}
      add :generated_by_agent, :string, null: false
      add :reviewed_at, :utc_datetime
      add :review_reason, :text
      add :slack_notification_requested_at, :utc_datetime
      add :slack_notification_posted_at, :utc_datetime
      add :slack_notification_channel_id, :string
      add :slack_notification_thread_ts, :string
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:outreach_recommendations, [:contact_id, :inserted_at])
    create index(:outreach_recommendations, [:account_id, :inserted_at])
    create index(:outreach_recommendations, [:source_event_id])
    create index(:outreach_recommendations, [:reviewed_by_id])

    create unique_index(:outreach_recommendations, [:contact_id],
             where: "status = 'pending'",
             name: :outreach_recommendations_pending_contact_index
           )

    create index(:outreach_recommendations, [:slack_notification_requested_at],
             where:
               "slack_notification_requested_at IS NOT NULL AND slack_notification_posted_at IS NULL",
             name: :outreach_recommendations_pending_slack_notification_index
           )

    create constraint(:outreach_recommendations, :outreach_recommendations_status_check,
             check: "status IN ('pending', 'completed', 'dismissed', 'superseded')"
           )

    create constraint(:outreach_recommendations, :outreach_recommendations_action_type_check,
             check:
               "action_type IN ('research', 'wait', 'engage', 'connection_request', 'message', 'reply', 'follow_up', 'nurture', 'stop')"
           )

    create constraint(:outreach_recommendations, :outreach_recommendations_event_kind_check,
             check:
               "recommended_event_kind IS NULL OR recommended_event_kind IN ('connection_requested', 'message_sent', 'note')"
           )

    create constraint(:outreach_recommendations, :outreach_recommendations_confidence_check,
             check: "confidence >= 0 AND confidence <= 1"
           )
  end
end
