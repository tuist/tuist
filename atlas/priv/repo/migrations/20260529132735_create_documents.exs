defmodule Atlas.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:document_correspondents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:document_correspondents, ["lower(name)"],
             name: :document_correspondents_lower_name_index
           )

    create table(:document_types, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:document_types, ["lower(name)"], name: :document_types_lower_name_index)

    create table(:document_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :color, :string, null: false, default: "neutral"

      timestamps()
    end

    create unique_index(:document_tags, ["lower(name)"], name: :document_tags_lower_name_index)

    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :original_filename, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :checksum_sha256, :string, null: false
      add :storage_bucket, :string, null: false
      add :storage_key, :string, null: false
      add :source, :string, null: false, default: "upload"
      add :status, :string, null: false, default: "uploaded"
      add :document_date, :date
      add :archive_serial_number, :integer
      add :attributes, :map, null: false, default: %{}
      add :summary, :text
      add :processed_at, :utc_datetime
      add :last_error, :text
      add :uploaded_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :correspondent_id,
          references(:document_correspondents, type: :binary_id, on_delete: :nilify_all)

      add :document_type_id, references(:document_types, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:documents, [:storage_bucket, :storage_key])
    create unique_index(:documents, [:archive_serial_number])
    create index(:documents, [:uploaded_by_id])
    create index(:documents, [:status])
    create index(:documents, [:correspondent_id])
    create index(:documents, [:document_type_id])
    create index(:documents, [:document_date])
    create index(:documents, [:inserted_at])

    create table(:documents_tags, primary_key: false) do
      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tag_id, references(:document_tags, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create unique_index(:documents_tags, [:document_id, :tag_id])
    create index(:documents_tags, [:tag_id])

    create table(:document_pages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :page_number, :integer, null: false
      add :content, :text, null: false
      add :embedding_model, :string
      add :embedded_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create unique_index(:document_pages, [:document_id, :page_number])
    create index(:document_pages, [:document_id])
  end
end
