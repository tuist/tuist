defmodule Tuist.Repo.Migrations.RemovePlanFromAccounts do
  use Ecto.Migration

  def up do
    alter table(:accounts) do
      remove(:plan)
      remove(:enterprise_plan_seats)
    end
  end

  def down do
    alter table(:accounts) do
      add(:plan, :integer, required: true, default: 0)
      add(:enterprise_plan_seats, :integer, required: false)
    end
  end
end
