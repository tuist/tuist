defmodule Atlas.Repo.Migrations.CreateCoordinationSystem do
  use Ecto.Migration

  def change do
    create table(:evidence_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :subject_type, :string, null: false
      add :subject_id, :binary_id, null: false
      add :record_type, :string, null: false
      add :record_id, :binary_id, null: false
      add :source_class, :string, null: false
      add :sensitivity, :string, null: false, default: "internal"
      add :observation, :text, null: false
      add :occurred_at, :utc_datetime, null: false
      add :position, :integer, null: false, default: 0

      timestamps(updated_at: false)
    end

    create unique_index(:evidence_links, [
             :subject_type,
             :subject_id,
             :record_type,
             :record_id
           ])

    create index(:evidence_links, [:record_type, :record_id])
    create index(:evidence_links, [:subject_type, :subject_id, :position])
    create index(:evidence_links, [:source_class, :occurred_at])

    create constraint(:evidence_links, :evidence_links_source_class_check,
             check:
               "source_class IN ('observed', 'human_asserted', 'agent_derived', 'decided', 'action_result')"
           )

    create constraint(:evidence_links, :evidence_links_sensitivity_check,
             check: "sensitivity IN ('public', 'internal', 'restricted')"
           )

    create constraint(:evidence_links, :evidence_links_subject_type_check,
             check:
               "subject_type IN ('account_outcome_proposal', 'account_outcome_review', 'outreach_recommendation', 'brief_item', 'cross_domain_claim')"
           )

    create constraint(:evidence_links, :evidence_links_record_type_check,
             check:
               "record_type IN ('account_event', 'account_term', 'finance_invoice', 'finance_transaction', 'account_outcome', 'account_outcome_review', 'outreach_message_attempt', 'product_trace', 'document', 'audit_activity', 'brief_item')"
           )

    create constraint(:evidence_links, :evidence_links_no_self_reference_check,
             check: "NOT (subject_type = record_type AND subject_id = record_id)"
           )

    create table(:brief_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string, null: false
      add :audience_key, :string, null: false
      add :cadence, :string, null: false
      add :domains, {:array, :string}, null: false
      add :slack_app, :string, null: false, default: "company"
      add :slack_channel_id, :string, null: false
      add :max_sensitivity, :string, null: false, default: "restricted"
      add :attention_budget, :integer, null: false, default: 8
      add :enabled, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:brief_subscriptions, [:audience_key, :cadence])
    create index(:brief_subscriptions, [:enabled, :cadence])

    create constraint(:brief_subscriptions, :brief_subscriptions_cadence_check,
             check: "cadence IN ('daily', 'weekly')"
           )

    create constraint(:brief_subscriptions, :brief_subscriptions_sensitivity_check,
             check: "max_sensitivity IN ('public', 'internal', 'restricted')"
           )

    create constraint(:brief_subscriptions, :brief_subscriptions_budget_check,
             check: "attention_budget > 0 AND attention_budget <= 20"
           )

    create constraint(:brief_subscriptions, :brief_subscriptions_domains_check,
             check:
               "cardinality(domains) > 0 AND domains <@ ARRAY['finance', 'accounts', 'outreach', 'product', 'company']::varchar[]"
           )

    create table(:briefs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :brief_subscription_id,
          references(:brief_subscriptions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :cadence, :string, null: false
      add :period_start, :utc_datetime, null: false
      add :period_end, :utc_datetime, null: false
      add :status, :string, null: false, default: "draft"
      add :headline, :text
      add :summary, :text
      add :attention_budget, :integer, null: false
      add :sensitivity, :string, null: false, default: "internal"
      add :generated_by_agent, :string
      add :generation_mode, :string
      add :slack_channel_id, :string
      add :slack_thread_ts, :string
      add :posted_at, :utc_datetime
      add :failure_reason, :text

      timestamps()
    end

    create unique_index(:briefs, [:brief_subscription_id, :cadence, :period_start])
    create index(:briefs, [:status, :period_start])
    create index(:briefs, [:cadence, :period_start])

    create constraint(:briefs, :briefs_cadence_check, check: "cadence IN ('daily', 'weekly')")

    create constraint(:briefs, :briefs_status_check,
             check: "status IN ('draft', 'material', 'immaterial', 'posted', 'failed')"
           )

    create constraint(:briefs, :briefs_generation_mode_check,
             check:
               "generation_mode IS NULL OR generation_mode IN ('agent', 'deterministic_fallback', 'deterministic')"
           )

    create constraint(:briefs, :briefs_sensitivity_check,
             check: "sensitivity IN ('public', 'internal', 'restricted')"
           )

    create constraint(:briefs, :briefs_attention_budget_check,
             check: "attention_budget > 0 AND attention_budget <= 20"
           )

    create table(:brief_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :brief_id, references(:briefs, type: :binary_id, on_delete: :delete_all), null: false
      add :domain, :string, null: false
      add :kind, :string, null: false
      add :title, :string, null: false
      add :detail, :text, null: false
      add :severity, :string, null: false
      add :sensitivity, :string, null: false
      add :materiality_score, :decimal, precision: 5, scale: 4, null: false
      add :confidence, :decimal, precision: 5, scale: 4
      add :suggested_action, :text
      add :completion_condition, :text
      add :fingerprint, :string, null: false
      add :source_type, :string
      add :source_id, :binary_id
      add :source_path, :string
      add :position, :integer, null: false
      add :status, :string, null: false, default: "open"
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :due_at, :utc_datetime
      add :resolved_at, :utc_datetime
      add :resolved_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :resolution_note, :text
      add :usefulness, :string
      add :usefulness_reason, :text
      add :usefulness_at, :utc_datetime
      add :usefulness_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:brief_items, [:brief_id, :fingerprint])
    create index(:brief_items, [:brief_id, :position])
    create index(:brief_items, [:domain, :status])
    create index(:brief_items, [:fingerprint, :inserted_at])

    create index(:brief_items, [:owner_id],
             where: "status = 'open'",
             name: :brief_items_open_owner_index
           )

    create index(:brief_items, [:usefulness],
             where: "usefulness IS NOT NULL",
             name: :brief_items_rated_index
           )

    create constraint(:brief_items, :brief_items_domain_check,
             check: "domain IN ('finance', 'accounts', 'outreach', 'product', 'company')"
           )

    create constraint(:brief_items, :brief_items_kind_check,
             check:
               "kind IN ('observation', 'concern', 'change', 'risk', 'follow_up', 'expectation_missed', 'proposal', 'claim')"
           )

    create constraint(:brief_items, :brief_items_severity_check,
             check: "severity IN ('info', 'warning', 'critical')"
           )

    create constraint(:brief_items, :brief_items_status_check,
             check:
               "status IN ('open', 'acknowledged', 'completed', 'dismissed', 'suppressed', 'expired')"
           )

    create constraint(:brief_items, :brief_items_usefulness_check,
             check: "usefulness IS NULL OR usefulness IN ('useful', 'not_useful')"
           )

    create constraint(:brief_items, :brief_items_materiality_check,
             check: "materiality_score >= 0 AND materiality_score <= 1"
           )

    create constraint(:brief_items, :brief_items_confidence_check,
             check: "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)"
           )

    create constraint(:brief_items, :brief_items_resolution_shape_check,
             check: "status NOT IN ('completed', 'dismissed') OR resolved_at IS NOT NULL"
           )

    create constraint(:brief_items, :brief_items_usefulness_shape_check,
             check: "(usefulness IS NULL) = (usefulness_at IS NULL)"
           )

    create table(:brief_suppressions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :brief_subscription_id,
          references(:brief_subscriptions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :domain, :string, null: false
      add :fingerprint, :string, null: false
      add :reason, :text, null: false
      add :suppressed_until, :utc_datetime

      # Severity of the item that was closed. A later escalation of the same
      # record outranks the suppression and reaches the brief anyway.
      add :severity, :string

      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :source_brief_item_id,
          references(:brief_items, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:brief_suppressions, [
             :brief_subscription_id,
             :domain,
             :fingerprint
           ])

    create index(:brief_suppressions, [:brief_subscription_id, :suppressed_until])

    create constraint(:brief_suppressions, :brief_suppressions_domain_check,
             check: "domain IN ('finance', 'accounts', 'outreach', 'product', 'company')"
           )

    create constraint(:brief_suppressions, :brief_suppressions_severity_check,
             check: "severity IS NULL OR severity IN ('info', 'warning', 'critical')"
           )
  end
end
