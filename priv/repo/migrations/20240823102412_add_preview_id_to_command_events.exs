defmodule Tuist.Repo.Migrations.AddPreviewIdToCommandEvents do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add :preview_id, :uuid, null: true
    end
  end
end
