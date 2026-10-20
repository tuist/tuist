defmodule Atlas.Repo.Migrations.AddFeatureFirstSeenAndDropAttention do
  use Ecto.Migration

  def up do
    # Nudge-owned first-appearance tracker. One row per (account, feature).
    # Populated by `Atlas.Nudges.Workers.RefreshFeatureFirstSeen` when it
    # spots an account's first `FeatureUsage.Snapshot` with any activity
    # for that feature. Signals in the "first X event" family fire once
    # off this transition.
    create table(:nudge_account_feature_first_seen, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :feature, :string, null: false
      add :first_use_at, :utc_datetime, null: false
      add :first_seen_computed_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:nudge_account_feature_first_seen, [:account_id, :feature])

    # Drop the deprecated account attention system. v1 (#13483) unwired every
    # writer and shrank `Atlas.Accounts.AccountAttention` to a read-only shell
    # for the transition window. That window has now elapsed, so the shell,
    # the schema, and the table all go.
    drop_if_exists table(:account_attention_suggestions)

    alter table(:accounts) do
      remove_if_exists :attention_context
      remove_if_exists :attention_suggestions_checked_at
    end
  end

  def down do
    alter table(:accounts) do
      add_if_not_exists :attention_context, :text
      add_if_not_exists :attention_suggestions_checked_at, :utc_datetime
    end

    create_if_not_exists table(:account_attention_suggestions, primary_key: false) do
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

    drop_if_exists unique_index(:nudge_account_feature_first_seen, [:account_id, :feature])
    drop_if_exists table(:nudge_account_feature_first_seen)
  end
end
