defmodule Tuist.Repo.Migrations.AllowUsWestKuraServiceRegion do
  use Ecto.Migration

  # `us-west` is a real service region that this table is the only route into:
  # `accounts.region` is `all | europe | usa`, and neither `usa` nor `all`
  # derives to it, so an account reaches us-west by explicit assignment or not
  # at all. The constraint predates the region and was rejecting it, which made
  # that placement impossible to record.
  def up do
    drop constraint(
           :kura_account_region_policies,
           :kura_account_region_policies_service_region_valid
         )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_account_region_policies,
             :kura_account_region_policies_service_region_valid,
             check: "service_region IN ('us-east', 'eu-central', 'us-west')"
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
