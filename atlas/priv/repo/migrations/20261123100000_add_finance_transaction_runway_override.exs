defmodule Atlas.Repo.Migrations.AddFinanceTransactionRunwayOverride do
  use Ecto.Migration

  def up do
    alter table(:finance_transactions) do
      add :runway_override, :boolean
    end

    execute("""
    INSERT INTO finance_categories (id, name, slug, description, direction, metadata, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'Financing',
      'financing',
      'Equity investments, loans, and other financing received from investors and lenders',
      'credit',
      '{}',
      now(),
      now()
    )
    ON CONFLICT (slug) DO NOTHING
    """)
  end

  def down do
    alter table(:finance_transactions) do
      remove :runway_override
    end
  end
end
