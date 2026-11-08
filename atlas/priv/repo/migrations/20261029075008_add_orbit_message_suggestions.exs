defmodule Atlas.Repo.Migrations.AddOrbitMessageSuggestions do
  use Ecto.Migration

  def change do
    alter table(:orbit_messages) do
      add :suggestions, {:array, :text}, default: [], null: false
    end
  end
end
