defmodule Atlas.Repo.Migrations.CreatePostmortems do
  use Ecto.Migration

  def change do
    create table(:postmortems, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:postmortems, [:inserted_at])
  end
end
