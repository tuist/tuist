defmodule Atlas.Repo.Migrations.AddResolutionUrlToPostmortemActionItems do
  use Ecto.Migration

  def change do
    alter table(:postmortem_action_items) do
      add :resolution_url, :text
    end
  end
end
