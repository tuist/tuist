defmodule Atlas.Repo.Migrations.AddAtlasAccountToFinanceSources do
  use Ecto.Migration

  def change do
    alter table(:finance_sources) do
      add :atlas_account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:finance_sources, [:atlas_account_id])
  end
end
