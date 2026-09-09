defmodule Tuist.Repo.Migrations.RenameEuCentralKuraRegionToEuWest do
  use Ecto.Migration

  # `eu-central` was named for the Hetzner Falkenstein pool it started on and
  # kept the name through the cutover to Scaleway Dedibox in Paris. The id is
  # published: it keys every region-scoped row and, through the cluster id,
  # every account's public hostname. This rewrites the rows; the hostnames
  # follow when the reconciler re-renders each instance against the renamed
  # catalog entry.
  #
  # `kura_servers.url` is not rewritten here: the reconciler replaces it only
  # once the new hostname resolves, so no client is handed a name that does not
  # answer yet. `provisioner_node_ref` is not rewritten either: it is an opaque
  # handle on the KuraInstance and its volumes, and rewriting it would orphan
  # both. `kura_deployments.cluster_id` is an audit field and is rewritten so
  # the history reads as one region.
  @region_columns [
    {:kura_servers, :region},
    {:kura_account_region_lifecycles, :service_region},
    {:kura_account_region_policies, :service_region},
    {:kura_placement_proposals, :from_region},
    {:kura_placement_proposals, :to_region},
    {:kura_placer_regions, :region},
    {:kura_storage_rollups, :region},
    {:kura_egress_limits, :region},
    {:kura_claim_proposals, :region},
    {:kura_registered_endpoints, :region}
  ]

  def up do
    drop constraint(
           :kura_account_region_policies,
           :kura_account_region_policies_service_region_valid
         )

    rename_region("eu-central", "eu-west")
    rename_cluster("eu-central-1", "eu-west-1")

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_account_region_policies,
             :kura_account_region_policies_service_region_valid,
             check:
               "service_region IN ('us-east', 'eu-west', 'us-west', 'ap-southeast', 'sa-west')"
           )
  end

  def down do
    drop constraint(
           :kura_account_region_policies,
           :kura_account_region_policies_service_region_valid
         )

    rename_region("eu-west", "eu-central")
    rename_cluster("eu-west-1", "eu-central-1")

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_account_region_policies,
             :kura_account_region_policies_service_region_valid,
             check:
               "service_region IN ('us-east', 'eu-central', 'us-west', 'ap-southeast', 'sa-west')"
           )
  end

  defp rename_region(from, to) do
    for {table, column} <- @region_columns do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("UPDATE #{table} SET #{column} = '#{to}' WHERE #{column} = '#{from}'")
    end
  end

  defp rename_cluster(from, to) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("UPDATE kura_deployments SET cluster_id = '#{to}' WHERE cluster_id = '#{from}'")
  end
end
