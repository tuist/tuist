defmodule Tuist.Repo.Migrations.AddRunnerEgressGatewayToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :runner_egress_gateway, :string
    end
  end
end
