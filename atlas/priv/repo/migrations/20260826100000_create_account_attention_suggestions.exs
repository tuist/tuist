defmodule Atlas.Repo.Migrations.CreateAccountAttentionSuggestions do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :attention_context, :text
      add :attention_suggestions_checked_at, :utc_datetime
    end

    create table(:account_attention_suggestions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :string, null: false, default: "pending"
      add :kind, :string, null: false
      add :suggestion_key, :string, null: false
      add :title, :string, null: false
      add :rationale, :text, null: false
      add :suggested_action, :text, null: false
      add :evidence, :map, null: false, default: %{"items" => []}
      add :confidence, :decimal, precision: 5, scale: 4, null: false
      add :generated_by_agent, :string, null: false
      add :snoozed_until, :utc_datetime
      add :resolved_at, :utc_datetime
      add :resolution_note, :text
      add :slack_channel_id, :string
      add :slack_thread_ts, :string
      add :posted_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:accounts, [:attention_suggestions_checked_at])
    create index(:account_attention_suggestions, [:account_id, :status])
    create index(:account_attention_suggestions, [:account_id, :suggestion_key, :inserted_at])
    create index(:account_attention_suggestions, [:status, :snoozed_until])

    create unique_index(:account_attention_suggestions, [:account_id, :suggestion_key],
             where: "status IN ('pending', 'snoozed')",
             name: :account_attention_suggestions_open_key_index
           )

    create constraint(:account_attention_suggestions, :account_attention_suggestions_status_check,
             check: "status IN ('pending', 'actioned', 'snoozed', 'dismissed')"
           )

    create constraint(:account_attention_suggestions, :account_attention_suggestions_kind_check,
             check:
               "kind IN ('follow_up', 'usage_change', 'renewal', 'adoption', 'value_proof', 'relationship')"
           )

    create constraint(
             :account_attention_suggestions,
             :account_attention_suggestions_confidence_check,
             check: "confidence >= 0 AND confidence <= 1"
           )
  end
end
