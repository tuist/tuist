defmodule Atlas.Repo.Migrations.CreateOutreachMessageAttempts do
  use Ecto.Migration

  def change do
    create table(:outreach_message_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :contact_id, references(:account_contacts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :recommendation_id,
          references(:outreach_recommendations, type: :binary_id, on_delete: :nilify_all)

      add :sent_event_id, references(:account_events, type: :binary_id, on_delete: :delete_all),
        null: false

      add :response_event_id,
          references(:account_events, type: :binary_id, on_delete: :nilify_all)

      add :channel, :string, null: false, default: "linkedin"
      add :message_kind, :string, null: false
      add :message_intent, :string
      add :personalization_source, :string
      add :call_to_action, :string
      add :proposed_message, :text
      add :sent_message, :text, null: false
      add :outcome, :string, null: false, default: "pending"
      add :sent_at, :utc_datetime, null: false
      add :outcome_at, :utc_datetime

      timestamps()
    end

    create index(:outreach_message_attempts, [:contact_id, :sent_at])
    create index(:outreach_message_attempts, [:account_id, :sent_at])
    create index(:outreach_message_attempts, [:recommendation_id])
    create unique_index(:outreach_message_attempts, [:sent_event_id])

    create unique_index(:outreach_message_attempts, [:response_event_id],
             where: "response_event_id IS NOT NULL"
           )

    create constraint(:outreach_message_attempts, :outreach_message_attempts_channel_check,
             check: "channel IN ('linkedin')"
           )

    create constraint(:outreach_message_attempts, :outreach_message_attempts_kind_check,
             check: "message_kind IN ('message', 'reply', 'follow_up', 'manual')"
           )

    create constraint(:outreach_message_attempts, :outreach_message_attempts_intent_check,
             check:
               "message_intent IS NULL OR message_intent IN ('understand_problem', 'deepen_context', 'offer_help', 'propose_evaluation')"
           )

    create constraint(
             :outreach_message_attempts,
             :outreach_message_attempts_personalization_source_check,
             check:
               "personalization_source IS NULL OR personalization_source IN ('recipient_message', 'public_work', 'account_signal', 'role_context')"
           )

    create constraint(:outreach_message_attempts, :outreach_message_attempts_call_to_action_check,
             check:
               "call_to_action IS NULL OR call_to_action IN ('question', 'resource_offer', 'meeting', 'none')"
           )

    create constraint(:outreach_message_attempts, :outreach_message_attempts_outcome_check,
             check:
               "outcome IN ('pending', 'replied', 'positive_reply', 'objection', 'not_interested', 'no_reply')"
           )
  end
end
