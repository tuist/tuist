defmodule Tuist.Repo.Migrations.RemoveCommandEventProjectIdFkey do
  use Ecto.Migration

  def up do
    drop constraint(:command_events, "command_events_project_id_fkey")
  end

  def down do
    alter table(:command_events) do
      modify :project_id, references(:projects, on_delete: :delete_all)
    end
  end
end
