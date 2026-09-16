defmodule Atlas.Repo.Migrations.AddFinanceTransactionCategories do
  use Ecto.Migration

  def change do
    create table(:finance_categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :direction, :string
      add :created_by_agent, :string
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:finance_categories, [:slug])
    create index(:finance_categories, [:direction])

    alter table(:finance_transactions) do
      add :finance_category_id,
          references(:finance_categories, type: :binary_id, on_delete: :nilify_all)

      add :categorized_at, :utc_datetime
      add :categorization_confidence, :decimal, precision: 5, scale: 4
      add :categorization_reason, :text
      add :categorized_by_agent, :string
    end

    create index(:finance_transactions, [:finance_category_id])
    create index(:finance_transactions, [:categorized_at])
  end
end
