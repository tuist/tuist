defmodule Atlas.Repo.Migrations.NumberPostmortems do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE postmortems_number_seq"

    alter table(:postmortems) do
      add :number, :bigint
    end

    execute """
    WITH numbered AS (
      SELECT id, row_number() OVER (ORDER BY inserted_at, id) AS number
      FROM postmortems
    )
    UPDATE postmortems
    SET number = numbered.number
    FROM numbered
    WHERE postmortems.id = numbered.id
    """

    execute """
    SELECT setval(
      'postmortems_number_seq',
      COALESCE((SELECT max(number) FROM postmortems), 0) + 1,
      false
    )
    """

    alter table(:postmortems) do
      modify :number, :bigint, null: false, default: fragment("nextval('postmortems_number_seq')")
    end

    create unique_index(:postmortems, [:number])
  end

  def down do
    drop_if_exists unique_index(:postmortems, [:number])

    alter table(:postmortems) do
      remove :number
    end

    execute "DROP SEQUENCE postmortems_number_seq"
  end
end
