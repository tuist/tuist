defmodule Tuist.Repo.Migrations.AddEntireCheckReports do
  use Ecto.Migration

  def change do
    # Older publishers require non-null discussion pointers. Keep their table
    # untouched so mixed-version replicas and application rollback remain safe.
    create table(:entire_trail_reports, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :connection_id,
          references(:entire_trail_connections, type: :uuid, on_delete: :delete_all), null: false

      add :trail_id, :string, null: false
      add :head_sha, :string, null: false
      add :report_body, :text, null: false
      add :reported_at, :timestamptz, null: false
      add :published_at, :timestamptz
      add :publication_started, :boolean, default: false, null: false
      add :findings, {:array, :map}, default: [], null: false
      add :review_id, :string
      add :finding_ids, {:array, :string}, default: [], null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:entire_trail_reports, [:connection_id, :trail_id])
  end
end
