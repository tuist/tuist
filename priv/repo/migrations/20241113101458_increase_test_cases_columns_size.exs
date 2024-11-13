defmodule Tuist.Repo.Migrations.IncreaseTestCasesColumnsSize do
  use Ecto.Migration

  def up do
    alter table(:test_cases) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :name, :string, size: 510
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :module_name, :string, size: 510
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :project_identifier, :string, size: 510
    end
  end

  def down do
    alter table(:test_cases) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :name, :string, size: 255
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :module_name, :string, size: 255
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :project_identifier, :string, size: 255
    end
  end
end
