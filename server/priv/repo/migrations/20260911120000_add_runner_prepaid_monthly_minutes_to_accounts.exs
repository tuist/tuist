defmodule Tuist.Repo.Migrations.AddRunnerPrepaidMonthlyMinutesToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :runner_prepaid_monthly_minutes, :integer
    end
  end
end
