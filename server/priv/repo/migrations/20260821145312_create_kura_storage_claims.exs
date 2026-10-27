defmodule Tuist.Repo.Migrations.CreateKuraStorageClaims do
  use Ecto.Migration

  # The claim an account's Kura volumes are built at, when its plan is the wrong
  # answer. Plan predicts an account's working set poorly in both directions:
  # accounts on the largest plan that never fill a fraction of their ring, and
  # accounts on the smallest that evict within days. A row here overrides the
  # plan-derived claim for every instance the account owns.
  #
  # Absence is the normal state and means "take the plan's claim", so there is
  # no default row to create and no backfill: every account starts unoverridden.
  def change do
    create table(:kura_storage_claims) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :claim_size, :string, null: false

      timestamps(type: :timestamptz)
    end

    # One override per account: the claim is a property of the account, applied
    # to whichever regions it holds an instance in.
    # The table is new and empty, so building its unique index inline cannot block writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_storage_claims, [:account_id])
  end
end
