defmodule Atlas.Repo.Migrations.CreatePortableSignals do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :business_profile, :map, null: false, default: %{}
    end

    alter table(:orbit_threads) do
      add :signal_reader_ids, {:array, :uuid}
    end

    create table(:signal_sources, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :text, null: false
      add :enabled, :boolean, null: false, default: false
      add :owner_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :revision_id, references(:automation_revisions, type: :uuid, on_delete: :restrict),
        null: false

      add :reader_ids, {:array, :uuid}, null: false
      add :required_scopes, {:array, :text}, null: false, default: []
      add :routing_roles, {:array, :text}, null: false, default: []
      timestamps(type: :utc_datetime_usec)
    end

    create table(:signals, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :source_id, references(:signal_sources, type: :uuid, on_delete: :delete_all),
        null: false

      add :thread_id, references(:orbit_threads, type: :uuid, on_delete: :nilify_all)
      add :execution_id, references(:automation_runs, type: :uuid, on_delete: :nilify_all)
      add :external_id, :text, null: false
      add :correlation_key, :text, null: false
      add :type, :text, null: false
      add :schema_version, :integer, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :envelope, :binary, null: false
      add :status, :text, null: false, default: "pending"
      add :priority, :text
      add :decision, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:signals, [:source_id, :external_id])
    create index(:signals, [:source_id, :status, :priority, :observed_at])
  end
end
