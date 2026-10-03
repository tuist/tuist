defmodule Atlas.Repo.Migrations.AddVisibilityToPostmortems do
  use Ecto.Migration

  def change do
    alter table(:postmortems) do
      add :visibility, :string, null: false, default: "public"
    end

    create index(:postmortems, [:visibility, :inserted_at])
  end
end
