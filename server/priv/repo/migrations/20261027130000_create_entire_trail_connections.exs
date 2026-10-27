defmodule Tuist.Repo.Migrations.CreateEntireTrailConnections do
  use Ecto.Migration

  def change do
    create table(:entire_trail_connections, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      add :installation_id, references(:ci_installations, type: :uuid, on_delete: :delete_all),
        null: false

      add :repository_id, :string, null: false
      add :repository_name, :string, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:entire_trail_connections, [:project_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:entire_trail_connections, [:installation_id, :repository_id])

    create table(:entire_trail_summaries, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :connection_id,
          references(:entire_trail_connections, type: :uuid, on_delete: :delete_all), null: false

      add :trail_id, :string, null: false
      add :discussion_id, :string, null: false
      add :message_id, :string, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:entire_trail_summaries, [:connection_id, :trail_id])
  end
end
