defmodule Atlas.Repo.Migrations.CreateAccountOutcomeProposals do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :outcome_proposals_checked_at, :utc_datetime
    end

    create table(:account_outcome_proposals, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :outcome_id, references(:account_outcomes, type: :binary_id, on_delete: :delete_all)
      add :source_event_id, references(:account_events, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :proposal_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :proposal_key, :string, null: false
      add :title, :string
      add :description, :text
      add :motion, :string
      add :success_measure, :text
      add :baseline, :text
      add :target, :text
      add :target_date, :date
      add :health, :string
      add :summary, :text
      add :recommendation, :text
      add :evidence, :map, null: false, default: %{"items" => []}
      add :confidence, :decimal, precision: 5, scale: 4, null: false
      add :rationale, :text, null: false
      add :generated_by_agent, :string, null: false
      add :reviewed_at, :utc_datetime
      add :rejection_reason, :text
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:account_outcome_proposals, [:account_id, :status])
    create index(:account_outcome_proposals, [:outcome_id, :status])
    create index(:account_outcome_proposals, [:source_event_id])
    create index(:account_outcome_proposals, [:reviewed_by_id])

    create unique_index(:account_outcome_proposals, [:account_id, :proposal_key],
             where: "status = 'pending'",
             name: :account_outcome_proposals_pending_key_index
           )

    create constraint(:account_outcome_proposals, :account_outcome_proposals_type_check,
             check: "proposal_type IN ('new_outcome', 'outcome_review')"
           )

    create constraint(:account_outcome_proposals, :account_outcome_proposals_status_check,
             check: "status IN ('pending', 'approved', 'rejected')"
           )

    create constraint(:account_outcome_proposals, :account_outcome_proposals_motion_check,
             check:
               "motion IS NULL OR motion IN ('evaluation', 'adoption', 'expansion', 'renewal', 'recovery')"
           )

    create constraint(:account_outcome_proposals, :account_outcome_proposals_health_check,
             check: "health IS NULL OR health IN ('unknown', 'on_track', 'at_risk', 'off_track')"
           )

    create constraint(:account_outcome_proposals, :account_outcome_proposals_confidence_check,
             check: "confidence >= 0 AND confidence <= 1"
           )

    create constraint(:account_outcome_proposals, :account_outcome_proposals_shape_check,
             check: """
             (proposal_type = 'new_outcome' AND title IS NOT NULL AND motion IS NOT NULL AND
               (outcome_id IS NULL OR status = 'approved'))
             OR
             (proposal_type = 'outcome_review' AND outcome_id IS NOT NULL AND health IS NOT NULL AND summary IS NOT NULL)
             """
           )
  end
end
