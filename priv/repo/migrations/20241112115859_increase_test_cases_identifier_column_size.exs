defmodule Tuist.Repo.Migrations.IncreaseTestCasesIdentifierColumnSize do
  use Ecto.Migration

  def up do
    alter table(:test_cases) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :identifier, :string, size: 510
    end
  end

  def down do
    alter table(:test_cases) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :identifier, :string, size: 255
    end
  end
end
