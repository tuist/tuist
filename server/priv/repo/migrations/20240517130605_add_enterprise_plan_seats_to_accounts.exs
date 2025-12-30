defmodule Tuist.Repo.Migrations.AddEnterprisePlanSeatsToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :enterprise_plan_seats, :integer, null: true
    end
  end
end
