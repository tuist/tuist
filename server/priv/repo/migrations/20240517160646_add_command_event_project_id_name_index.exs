defmodule Tuist.Repo.Migrations.AddCommandEventProjectIdNameIndex do
  use Ecto.Migration

  def change do
    create index(:command_events, [:name, :project_id])
  end
end
