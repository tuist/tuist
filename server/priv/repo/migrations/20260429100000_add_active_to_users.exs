defmodule Tuist.Repo.Migrations.AddActiveToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :active, :boolean, default: true, null: false
    end
  end
end
