defmodule Tuist.Repo.Migrations.AllowSupersededKuraDeploymentStatus do
  use Ecto.Migration

  # Widens the deployment status check to admit `:superseded` (5): the terminal
  # state for an open deployment displaced by a newer released image tag. The
  # partial "one open deployment per server" index keys off `status IN (0, 1)`,
  # so a superseded row stops counting as open and the newer tag can be
  # scheduled in the same tick. Only pre-existing statuses (0..4) exist today,
  # and they satisfy the wider predicate, so the swap validates instantly.

  def up do
    drop constraint(:kura_deployments, :kura_deployments_status_valid)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_deployments, :kura_deployments_status_valid,
             check: "status IN (0, 1, 2, 3, 4, 5)"
           )
  end

  def down do
    drop constraint(:kura_deployments, :kura_deployments_status_valid)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_deployments, :kura_deployments_status_valid,
             check: "status IN (0, 1, 2, 3, 4)"
           )
  end
end
