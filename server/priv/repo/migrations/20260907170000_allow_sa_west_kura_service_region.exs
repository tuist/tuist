defmodule Tuist.Repo.Migrations.AllowSaWestKuraServiceRegion do
  use Ecto.Migration

  # `sa-west` (Santiago) is a real service region that this table is the only
  # route into, exactly like `us-west` and `ap-southeast`: `accounts.region` is
  # `all | europe | usa`, and none of those derive to South America, so an
  # account reaches it by explicit assignment, by picking it in account
  # settings, or through a placement proposal. Widening the constraint ahead of
  # the hardware joining the cluster is deliberate: an assignment has to be
  # recordable before the box it names can be placed into service, and
  # TUIST_KURA_AVAILABLE_REGIONS is what keeps the region unserved until then.
  def up do
    drop constraint(
           :kura_account_region_policies,
           :kura_account_region_policies_service_region_valid
         )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_account_region_policies,
             :kura_account_region_policies_service_region_valid,
             check:
               "service_region IN ('us-east', 'eu-central', 'us-west', 'ap-southeast', 'sa-west')"
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
             check: "service_region IN ('us-east', 'eu-central', 'us-west', 'ap-southeast')"
           )
  end
end
