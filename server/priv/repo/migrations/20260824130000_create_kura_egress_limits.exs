defmodule Tuist.Repo.Migrations.CreateKuraEgressLimits do
  use Ecto.Migration

  # The egress floor and ceiling an account's Kura pods are shaped at in one
  # region, when that region's own numbers are the wrong answer for it. A
  # region's pair is sized for the boxes its instances share rather than for any
  # tenant on them, so a single account that restores far more than its
  # neighbours (or one that must be held well under the shared ceiling) has no
  # way to be treated differently.
  #
  # Scoped to a region rather than to an account because the boxes differ: each
  # declares its own egress budget, so a floor a 3 Gbit/s box can keep is one a
  # 1 Gbit/s box cannot, and one account-wide number would either waste the roomy
  # regions or promise what the small ones cannot deliver.
  #
  # Either rate column may be null on its own: an operator overriding only the
  # ceiling leaves the floor resolving from the region, and the other way round.
  # Absence of the row is the normal state and means "take the region's pair", so
  # there is no default row to create and no backfill.
  def change do
    create table(:kura_egress_limits) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :region, :string, null: false
      add :floor_mbps, :integer
      add :burst_mbps, :integer

      timestamps(type: :timestamptz)
    end

    # One override per account per region.
    # The table is new and empty, so building its unique index inline cannot block writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_egress_limits, [:account_id, :region])
  end
end
