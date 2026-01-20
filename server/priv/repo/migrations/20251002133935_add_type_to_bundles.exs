defmodule Tuist.Repo.Migrations.AddTypeToBundles do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def change do
    alter table(:bundles) do
      add :type, :integer, null: false, default: 1
    end
  end
end
