defmodule Tuist.Repo.Migrations.AllowApSoutheastKuraServiceRegion do
  use Ecto.Migration

  # `ap-southeast` (Singapore) is a real service region that this table is the
  # only route into, exactly like `us-west`: `accounts.region` is `all | europe
  # | usa`, and none of those derive to Asia Pacific, so an APAC account reaches
  # it by explicit assignment or not at all. Widening the constraint ahead of
  # the hardware is deliberate — an assignment has to be recordable before the
  # box it names can be placed into service, and TUIST_KURA_AVAILABLE_REGIONS is
  # what keeps the region unserved until then.
  def up do
    drop constraint(
           :kura_account_region_policies,
           :kura_account_region_policies_service_region_valid
         )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_account_region_policies,
             :kura_account_region_policies_service_region_valid,
             check: "service_region IN ('us-east', 'eu-central', 'us-west', 'ap-southeast')"
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
             check: "service_region IN ('us-east', 'eu-central', 'us-west')"
           )
  end
end
