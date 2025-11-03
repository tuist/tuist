defmodule Tuist.Repo.Migrations.AddRegionToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :region, :integer, default: 0, null: false
    end
  end
end
