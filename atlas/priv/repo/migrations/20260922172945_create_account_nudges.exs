defmodule Atlas.Repo.Migrations.CreateAccountNudges do
  use Ecto.Migration

  def change do
    create table(:account_nudges, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :contact_id, references(:account_contacts, type: :binary_id, on_delete: :nilify_all)
      add :claimed_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :signal, :string, null: false
      add :dedup_key, :string, null: false
      add :state, :string, null: false, default: "pending_post"
      add :severity, :string, null: false, default: "normal"

      add :title, :string, null: false
      add :rationale, :text, null: false
      add :evidence, :map, null: false, default: %{}

      add :draft_subject, :string, null: false
      add :draft_body, :text, null: false

      add :claimed_at, :utc_datetime
      add :dismissed_at, :utc_datetime
      add :dismissed_reason, :text
      add :dismissed_until, :utc_datetime
      add :expired_at, :utc_datetime

      add :slack_channel_id, :string
      add :slack_message_ts, :string

      add :expires_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:account_nudges, [:account_id, :state])
    create index(:account_nudges, [:state, :expires_at])
    create index(:account_nudges, [:signal, :inserted_at])
    create index(:account_nudges, [:claimed_by_user_id])

    create unique_index(:account_nudges, [:account_id, :dedup_key],
             where: "state IN ('pending_post', 'proposed', 'claimed')",
             name: :account_nudges_open_dedup_index
           )

    create constraint(:account_nudges, :account_nudges_state_check,
             check: "state IN ('pending_post', 'proposed', 'claimed', 'dismissed', 'expired')"
           )

    create constraint(:account_nudges, :account_nudges_severity_check,
             check: "severity IN ('low', 'normal', 'high')"
           )

    create constraint(:account_nudges, :account_nudges_dismissed_reason_check,
             check:
               "state <> 'dismissed' OR (dismissed_reason IS NOT NULL AND dismissed_reason <> '')"
           )

    create table(:nudge_signal_episodes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :signal, :string, null: false
      add :state, :string, null: false, default: "open"
      add :opened_at, :utc_datetime, null: false
      add :closed_at, :utc_datetime
      add :evidence, :map, null: false, default: %{}

      timestamps()
    end

    create index(:nudge_signal_episodes, [:account_id, :signal, :state])

    create unique_index(:nudge_signal_episodes, [:account_id, :signal],
             where: "state = 'open'",
             name: :nudge_signal_episodes_open_index
           )

    create constraint(:nudge_signal_episodes, :nudge_signal_episodes_state_check,
             check: "state IN ('open', 'closed')"
           )

    create table(:nudge_slack_post_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :nudge_id, references(:account_nudges, type: :binary_id, on_delete: :delete_all),
        null: false

      add :client_msg_id, :string, null: false
      add :channel_id, :string, null: false
      add :message_ts, :string
      add :state, :string, null: false, default: "pending"
      add :last_error, :text
      add :attempts, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:nudge_slack_post_attempts, [:client_msg_id])
    create index(:nudge_slack_post_attempts, [:nudge_id])

    create constraint(:nudge_slack_post_attempts, :nudge_slack_post_attempts_state_check,
             check: "state IN ('pending', 'posted', 'failed')"
           )
  end
end
