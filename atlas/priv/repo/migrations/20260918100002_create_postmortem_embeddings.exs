defmodule Atlas.Repo.Migrations.CreatePostmortemEmbeddings do
  use Ecto.Migration

  def change do
    create table(:postmortem_embeddings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :postmortem_id, references(:postmortems, type: :binary_id, on_delete: :delete_all),
        null: false

      add :content_hash, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :embedding, {:array, :float}
      add :failure_reason, :string
      add :indexed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:postmortem_embeddings, [:postmortem_id])
    create index(:postmortem_embeddings, [:status])
  end
end
