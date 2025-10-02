defmodule Tuist.Repo.Migrations.AddTypeToBundles do
  use Ecto.Migration

  def change do
    alter table(:bundles) do
      add :type, :integer, null: false, default: 1
    end
  end
end
