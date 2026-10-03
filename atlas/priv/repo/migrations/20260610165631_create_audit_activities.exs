defmodule Atlas.Repo.Migrations.CreateAuditActivities do
  use Ecto.Migration

  def change do
    create table(:audit_activities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :action, :string, null: false
      add :interface, :string, null: false
      add :occurred_at, :utc_datetime, null: false

      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :actor_email, :string
      add :actor_name, :string
      add :actor_role, :string

      add :target_type, :string
      add :target_id, :string
      add :target_label, :string
      add :metadata, :map, default: %{}, null: false

      timestamps()
    end

    create index(:audit_activities, [:occurred_at])
    create index(:audit_activities, [:interface, :occurred_at])
    create index(:audit_activities, [:action, :occurred_at])
    create index(:audit_activities, [:actor_id, :occurred_at])
    create index(:audit_activities, [:target_type, :target_id, :occurred_at])
  end
end
