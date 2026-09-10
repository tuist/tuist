defmodule Tuist.Repo.Migrations.AllowEuEastAndUsCentralKuraServiceRegions do
  use Ecto.Migration

  # `eu-east` (Warsaw) and `us-central` (Chicago), on the same terms as
  # `sa-west` before them. `accounts.region` is `all | europe | usa`, so neither
  # derives from it: an account reaches either by explicit assignment, by
  # picking it in account settings, or through a placement proposal. Widening
  # ahead of the hardware joining the cluster is deliberate, because an
  # assignment has to be recordable before the box it names can be placed into
  # service, and TUIST_KURA_AVAILABLE_REGIONS is what keeps both unserved until
  # then.
  def up do
    drop(
      constraint(
        :kura_account_region_policies,
        :kura_account_region_policies_service_region_valid
      )
    )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create(
      constraint(
        :kura_account_region_policies,
        :kura_account_region_policies_service_region_valid,
        check:
          "service_region IN ('us-east', 'eu-central', 'us-west', 'ap-southeast', 'sa-west', 'eu-east', 'us-central')"
      )
    )
  end

  def down do
    drop(
      constraint(
        :kura_account_region_policies,
        :kura_account_region_policies_service_region_valid
      )
    )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create(
      constraint(
        :kura_account_region_policies,
        :kura_account_region_policies_service_region_valid,
        check: "service_region IN ('us-east', 'eu-central', 'us-west', 'ap-southeast', 'sa-west')"
      )
    )
  end
end
