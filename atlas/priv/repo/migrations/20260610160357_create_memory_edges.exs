defmodule Atlas.Repo.Migrations.CreateMemoryEdges do
  use Ecto.Migration

  def change do
    create table(:memory_edges, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :src_id,
          references(:memory_nodes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :dst_id,
          references(:memory_nodes, type: :binary_id, on_delete: :delete_all),
          null: false

      add :kind, :string, null: false
      add :weight, :float, null: false, default: 1.0

      timestamps()
    end

    create unique_index(:memory_edges, [:src_id, :dst_id, :kind])
    create index(:memory_edges, [:src_id])
    create index(:memory_edges, [:dst_id])
    create index(:memory_edges, [:kind])
  end
end
