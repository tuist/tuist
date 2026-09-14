defmodule Tuist.Repo.Migrations.CreateKuraClaimProposals do
  use Ecto.Migration

  # One record type carries claim sizing through its rollout phases: the sweep
  # writes proposals (shadow), an operator confirms them from the ops account
  # page (supervised), and with the automatic flag on the sweep applies them
  # itself. Applied, dismissed, and superseded proposals stay as the audit
  # trail of what sizing did and why.
  def change do
    create table(:kura_claim_proposals, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :region, :string, null: false
      add :direction, :string, null: false
      add :current_claim_size, :string, null: false
      add :recommended_claim_size, :string, null: false
      add :evidence, :map, null: false, default: %{}
      add :status, :string, null: false, default: "open"
      add :resolved_at, :timestamptz
      add :resolved_by, :string

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_claim_proposals, [:account_id])

    # Claims are account-scoped, so at most one proposal can be actionable per
    # account at a time; a changed recommendation supersedes the open one.
    # The table is new and empty, so building its unique index inline cannot block writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_claim_proposals, [:account_id],
             where: "status = 'open'",
             name: :kura_claim_proposals_one_open_per_account
           )
  end
end
