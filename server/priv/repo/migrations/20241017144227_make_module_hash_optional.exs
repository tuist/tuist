defmodule Tuist.Repo.Migrations.MakeModuleHashOptional do
  use Ecto.Migration

  def up do
    alter table(:test_case_runs) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :module_hash, :string, null: true
    end
  end

  def down do
    alter table(:test_case_runs) do
      # excellent_migrations:safety-assured-for-next-line not_null_added column_type_changed
      modify :module_hash, :string, null: false
    end
  end
end
