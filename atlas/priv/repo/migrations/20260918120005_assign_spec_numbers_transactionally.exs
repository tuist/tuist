defmodule Atlas.Repo.Migrations.AssignSpecNumbersTransactionally do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE specs ALTER COLUMN number DROP DEFAULT"
    execute "DROP SEQUENCE IF EXISTS specs_number_seq"
  end

  def down do
    execute "CREATE SEQUENCE IF NOT EXISTS specs_number_seq"

    execute """
    SELECT setval(
      'specs_number_seq',
      COALESCE((SELECT max(number) FROM specs), 0) + 1,
      false
    )
    """

    execute "ALTER TABLE specs ALTER COLUMN number SET DEFAULT nextval('specs_number_seq')"
  end
end
