defmodule Atlas.Repo.Migrations.AddNumberAndSummaryToSpecs do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE specs_number_seq"

    alter table(:specs) do
      add :number, :bigint
      add :summary, :string
    end

    execute """
    WITH numbered AS (
      SELECT id, row_number() OVER (ORDER BY inserted_at, id) AS number
      FROM specs
    )
    UPDATE specs
    SET number = numbered.number
    FROM numbered
    WHERE specs.id = numbered.id
    """

    execute """
    SELECT setval(
      'specs_number_seq',
      COALESCE((SELECT max(number) FROM specs), 0) + 1,
      false
    )
    """

    alter table(:specs) do
      modify :number, :bigint, null: false, default: fragment("nextval('specs_number_seq')")
    end

    create unique_index(:specs, [:number])
  end

  def down do
    drop_if_exists unique_index(:specs, [:number])

    alter table(:specs) do
      remove :summary
      remove :number
    end

    execute "DROP SEQUENCE specs_number_seq"
  end
end
