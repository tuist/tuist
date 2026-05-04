defmodule Tuist.Repo.Migrations.AddKuraDeploymentsStatusConstraint do
  use Ecto.Migration

  def change do
    create constraint(:kura_deployments, :kura_deployments_status_valid,
             check: "status IN (0, 1, 2, 3, 4)"
           )
  end
end
