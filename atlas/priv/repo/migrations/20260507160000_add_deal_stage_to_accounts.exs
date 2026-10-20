defmodule Atlas.Repo.Migrations.AddDealStageToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :deal_stage, :string
    end

    create index(:accounts, [:deal_stage])
  end
end
