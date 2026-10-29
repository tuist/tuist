defmodule Atlas.Repo.Migrations.AddAuthorToPostmortems do
  use Ecto.Migration

  def change do
    alter table(:postmortems) do
      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:postmortems, [:created_by_user_id])
  end
end
