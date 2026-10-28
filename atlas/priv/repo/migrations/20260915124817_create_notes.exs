defmodule Atlas.Repo.Migrations.CreateNotes do
  use Ecto.Migration

  def change do
    create table(:notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :content, :text, null: false
      # The field is intentionally narrow for now. It gives the domain a stable
      # seam for introducing per-note visibility rules later.
      add :visibility, :string, null: false, default: "authenticated"
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:notes, [:created_by_id])
    create index(:notes, [:visibility])
    create index(:notes, [:inserted_at])

    create index(
             :notes,
             ["to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, ''))"],
             using: "gin",
             name: :notes_fulltext_index
           )
  end
end
