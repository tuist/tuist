defmodule Atlas.Repo.Migrations.AddDescriptionToPostmortemActionItems do
  use Ecto.Migration

  def change do
    alter table(:postmortem_action_items) do
      add :description, :text
    end
  end
end
