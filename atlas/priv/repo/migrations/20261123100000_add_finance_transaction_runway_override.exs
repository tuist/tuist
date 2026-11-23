defmodule Atlas.Repo.Migrations.AddFinanceTransactionRunwayOverride do
  use Ecto.Migration

  def change do
    alter table(:finance_transactions) do
      add :runway_override, :boolean
    end
  end
end
