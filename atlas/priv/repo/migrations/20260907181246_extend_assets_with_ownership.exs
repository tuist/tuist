defmodule Atlas.Repo.Migrations.ExtendAssetsWithOwnership do
  use Ecto.Migration

  def change do
    # Step 1: add nullable columns without a default so the backfill can
    # target existing rows via `WHERE ownership IS NULL`.
    alter table(:assets) do
      add :ownership, :string
      add :ownership_acquired_on, :date
    end

    execute(
      "UPDATE assets SET ownership = 'owned', ownership_acquired_on = purchased_on WHERE ownership IS NULL",
      "UPDATE assets SET ownership = NULL, ownership_acquired_on = NULL"
    )

    # Step 2: set the default and NOT NULL after the backfill.
    alter table(:assets) do
      modify :ownership, :string, null: false, default: "owned"
    end

    # Step 3: drop the phase-1 NOT NULL on purchased_on and add the
    # conditional check that allows null purchased_on when the asset is
    # leased.
    alter table(:assets) do
      modify :purchased_on, :date, null: true
    end

    create constraint(:assets, :assets_purchased_on_required,
             check: "purchased_on IS NOT NULL OR ownership = 'leased'"
           )

    create constraint(:assets, :assets_ownership_check,
             check: "ownership IN ('owned','leased','unknown')"
           )

    create constraint(:assets, :assets_ownership_acquired_on_iff_owned,
             check: "(ownership_acquired_on IS NOT NULL) OR (ownership <> 'owned')"
           )

    # Step 4: replace the phase-1 state check to add the new
    # :returned_to_lessor terminal state used by lease-return workflows.
    drop constraint(:assets, :assets_state_check)

    create constraint(:assets, :assets_state_check,
             check:
               "state IN ('in_service','in_storage','in_repair','retired','disposed','lost','returned_to_lessor')"
           )

    # Step 5: reconcile retire/return constraints. Split the phase-1
    # equivalence into two directional checks so a previously retired
    # asset can subsequently move to :returned_to_lessor while
    # preserving its retired_on history.
    drop constraint(:assets, :assets_retired_state_has_date)

    create constraint(:assets, :assets_retired_state_has_date,
             check: "state NOT IN ('retired','disposed') OR retired_on IS NOT NULL"
           )

    create constraint(:assets, :assets_retired_on_allowed_states,
             check: "retired_on IS NULL OR state IN ('retired','disposed','returned_to_lessor')"
           )
  end
end
