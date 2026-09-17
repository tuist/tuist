defmodule Atlas.Repo.Migrations.ReplaceActionItemsAndPriorityWithOutcomes do
  use Ecto.Migration

  def up do
    create table(:account_outcomes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :source_event_id, references(:account_events, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "active"
      add :health, :string, null: false, default: "unknown"
      add :motion, :string, null: false, default: "adoption"
      add :title, :string, null: false
      add :description, :text
      add :success_measure, :text
      add :baseline, :text
      add :target, :text
      add :target_date, :date
      add :reviewed_at, :utc_datetime
      add :achieved_at, :utc_datetime
      add :closed_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:account_outcomes, [:account_id, :status])
    create index(:account_outcomes, [:account_id, :health])
    create index(:account_outcomes, [:status, :health])
    create index(:account_outcomes, [:target_date])
    create index(:account_outcomes, [:owner_id])
    create index(:account_outcomes, [:source_event_id])

    create table(:account_outcome_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :outcome_id,
          references(:account_outcomes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :health, :string, null: false
      add :summary, :text, null: false
      add :evidence, :map, null: false, default: %{"items" => []}
      add :recommendation, :text
      add :reviewed_at, :utc_datetime, null: false
      add :created_by_agent, :string
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:account_outcome_reviews, [:outcome_id, :reviewed_at])
    create index(:account_outcome_reviews, [:author_id])

    execute("""
    INSERT INTO account_events (
      id,
      account_id,
      author_id,
      external_id,
      source,
      kind,
      title,
      body,
      occurred_at,
      metadata,
      inserted_at
    )
    SELECT
      gen_random_uuid(),
      account_id,
      created_by_user_id,
      'legacy-action-item:' || id::text,
      'atlas',
      'legacy_action_item',
      title,
      body,
      inserted_at,
      COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
        'legacy_action_item_id', id,
        'status', status,
        'kind', kind,
        'source', source,
        'created_by_agent', created_by_agent,
        'due_at', due_at,
        'completed_at', completed_at,
        'dismissed_at', dismissed_at,
        'triggering_event_id', triggering_event_id
      ),
      inserted_at
    FROM account_action_items
    ON CONFLICT (source, external_id) DO NOTHING
    """)

    execute("DELETE FROM search_records WHERE source_type = 'account_action_item'")

    drop table(:account_action_items)

    drop_if_exists index(:accounts, [:priority])
    drop_if_exists index(:accounts, [:customer_pulse_company_slack_posted_at])

    rename table(:accounts), :customer_pulse_company_slack_posted_at,
      to: :outcome_review_company_slack_posted_at

    create index(:accounts, [:outcome_review_company_slack_posted_at])

    alter table(:accounts) do
      remove :priority
      remove :priority_reason
      remove :priority_signals
      remove :priority_previous
      remove :priority_changed_at
      remove :priority_updated_at
    end
  end

  def down do
    alter table(:accounts) do
      add :priority, :string
      add :priority_reason, :text
      add :priority_signals, :map, default: %{"items" => []}, null: false
      add :priority_previous, :string
      add :priority_changed_at, :utc_datetime
      add :priority_updated_at, :utc_datetime
    end

    create index(:accounts, [:priority])

    drop_if_exists index(:accounts, [:outcome_review_company_slack_posted_at])

    rename table(:accounts), :outcome_review_company_slack_posted_at,
      to: :customer_pulse_company_slack_posted_at

    create index(:accounts, [:customer_pulse_company_slack_posted_at])

    create table(:account_action_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "open"
      add :kind, :string
      add :title, :string, null: false
      add :body, :text
      add :due_at, :utc_datetime
      add :source, :string, null: false
      add :created_by_agent, :string

      add :triggering_event_id,
          references(:account_events, type: :binary_id, on_delete: :nilify_all)

      add :completed_at, :utc_datetime
      add :dismissed_at, :utc_datetime
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create index(:account_action_items, [:account_id, :status])
    create index(:account_action_items, [:account_id, :status, :due_at])
    create index(:account_action_items, [:status])
    create index(:account_action_items, [:triggering_event_id])

    execute("DELETE FROM account_events WHERE source = 'atlas' AND kind = 'legacy_action_item'")

    drop table(:account_outcome_reviews)
    drop table(:account_outcomes)
  end
end
