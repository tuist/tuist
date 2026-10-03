defmodule Atlas.Repo.Migrations.AddAccountToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:documents, [:account_id])
  end
end
