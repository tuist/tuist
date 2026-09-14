defmodule Tuist.Repo.Migrations.AddRunnerPrepaidGrantedPeriodStartToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :runner_prepaid_granted_period_start, :timestamptz
    end
  end
end
