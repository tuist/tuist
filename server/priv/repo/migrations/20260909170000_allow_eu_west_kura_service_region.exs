defmodule Tuist.Repo.Migrations.AllowEuWestKuraServiceRegion do
  use Ecto.Migration

  # `eu-west` (Paris) is the correctly named successor to `eu-central`, which
  # has always been Paris despite its id. It is added beside `eu-central` rather
  # than replacing it: the old id is stamped on live kura_servers rows and mints
  # every account's public hostname, so accounts are relocated across by
  # placement and `eu-central` is retired once drained, rather than the id being
  # mutated underneath them.
  #
  # Widening the constraint ahead of the hardware is the same order `sa-west`
  # took: an assignment has to be recordable before the boxes it names can be
  # placed into service, and TUIST_KURA_AVAILABLE_REGIONS is what keeps the
  # region unserved until the Dedibox fleet is split between the two pools.
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
               "service_region IN ('us-east', 'eu-central', 'eu-west', 'us-west', 'ap-southeast', 'sa-west')"
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
             check:
               "service_region IN ('us-east', 'eu-central', 'us-west', 'ap-southeast', 'sa-west')"
           )
  end
end
