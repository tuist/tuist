defmodule Atlas.Repo.Migrations.CreateSearchRecords do
  use Ecto.Migration

  def change do
    create table(:search_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_type, :string, null: false
      add :source_id, :string, null: false
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
      add :title, :string, null: false
      add :body, :text
      add :path, :string
      add :metadata, :map, null: false, default: %{}
      add :embedding_model, :string
      add :embedded_at, :utc_datetime

      timestamps()
    end

    create unique_index(:search_records, [:source_type, :source_id])
    create index(:search_records, [:source_type])
    create index(:search_records, [:account_id])
    create index(:search_records, [:inserted_at])

    create index(
             :search_records,
             ["to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, ''))"],
             using: "gin",
             name: :search_records_fulltext_index
           )
  end
end
