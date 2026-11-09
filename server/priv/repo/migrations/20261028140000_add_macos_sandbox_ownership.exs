defmodule Tuist.Repo.Migrations.AddMacosSandboxOwnership do
  use Ecto.Migration

  def change do
    alter table(:sandbox_agent_environments) do
      # PostgreSQL 11+ stores these constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :platform, :string, null: false, default: "linux"
    end

    alter table(:sandboxes) do
      # PostgreSQL 11+ stores these constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :platform, :string, null: false, default: "linux"
      add :node_uid, :string
      # PostgreSQL 11+ stores these constant defaults without rewriting existing rows.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :resident, :boolean, null: false, default: false
    end
  end
end
