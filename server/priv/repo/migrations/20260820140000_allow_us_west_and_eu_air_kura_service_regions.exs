defmodule Tuist.Repo.Migrations.AllowUsWestAndEuAirKuraServiceRegions do
  use Ecto.Migration

  # Widens the column to the two region ids the original constraint predates.
  #
  # `us-west` is a real service region that this table is the only route into:
  # `accounts.region` is `all | europe | usa`, and neither `usa` nor `all`
  # derives to it, so an account reaches us-west by explicit assignment or not
  # at all. The constraint rejecting it made that placement impossible.
  #
  # `eu-air` is the European Air pool, added so the column's vocabulary stays
  # aligned with the region catalog. The application-level assignable set
  # (`Tuist.Kura.AccountRegionPolicy`) deliberately stays narrower and excludes
  # it: that pool is a single best-effort box with no recovery machine behind
  # it, sized for Air's memory profile, and pinning a paid account there would
  # undo the tier separation the pool exists to keep.
  def up do
    drop constraint(
           :kura_account_region_policies,
           :kura_account_region_policies_service_region_valid
         )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_account_region_policies,
             :kura_account_region_policies_service_region_valid,
             check: "service_region IN ('us-east', 'eu-central', 'us-west', 'eu-air')"
           )
  end

  def down do
    drop constraint(
           :kura_account_region_policies,
           :kura_account_region_policies_service_region_valid
         )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_account_region_policies,
             :kura_account_region_policies_service_region_valid,
             check: "service_region IN ('us-east', 'eu-central')"
           )
  end
end
