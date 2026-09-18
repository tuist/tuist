defmodule Atlas.Repo.Migrations.CreatePostmortemActionItems do
  use Ecto.Migration

  def change do
    create table(:postmortem_action_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :text, null: false
      add :completed_at, :utc_datetime

      add :postmortem_id, references(:postmortems, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:postmortem_action_items, [:postmortem_id, :completed_at, :inserted_at])
  end
end
