defmodule Tuist.Repo.Migrations.AddReplicatedToChToBundles do
  use Ecto.Migration

  def change do
    alter table(:bundles) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :replicated_to_ch, :boolean, default: false, null: false
    end
  end
end
