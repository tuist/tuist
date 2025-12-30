defmodule Tuist.Repo.Migrations.CreateQaLaunchArgumentGroups do
  use Ecto.Migration

  def change do
    create table(:qa_launch_argument_groups, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :value, :text, null: false

      timestamps(type: :timestamptz)
    end

    create index(:qa_launch_argument_groups, [:name])
    create unique_index(:qa_launch_argument_groups, [:project_id, :name])
  end
end
