defmodule Tuist.Repo.Migrations.DropQaTablesAndColumns do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:qa_screenshots)
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:qa_recordings)
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:qa_steps)
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:qa_runs)
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:qa_launch_argument_groups)

    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :qa_app_description
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :qa_email
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :qa_password
    end
  end

  def down do
    create table(:qa_launch_argument_groups, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :value, :text, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:qa_launch_argument_groups, [:name])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:qa_launch_argument_groups, [:project_id, :name])

    create table(:qa_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :app_build_id, references(:app_builds, type: :uuid, on_delete: :delete_all)
      add :prompt, :text, null: false
      add :status, :string, null: false, default: "pending"
      add :summary, :text
      add :branch, :string
      add :commit_sha, :string
      add :pull_request_number, :integer
      add :github_issue_comment_id, :bigint
      add :finished_at, :timestamptz
      add :launch_argument_groups_id, {:array, :uuid}
      add :app_description, :text
      add :email, :text
      add :password, :text
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:qa_runs, [:status])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:qa_runs, [:inserted_at])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:qa_runs, [:app_build_id])

    create table(:qa_steps, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :qa_run_id, references(:qa_runs, type: :uuid, on_delete: :delete_all), null: false
      add :action, :text, null: false
      add :result, :text
      add :issues, :jsonb, null: false
      add :started_at, :timestamptz
      add :inserted_at, :timestamptz, null: false
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:qa_steps, [:qa_run_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:qa_steps, [:inserted_at])

    create table(:qa_screenshots, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :qa_run_id, references(:qa_runs, type: :uuid, on_delete: :delete_all), null: false
      add :qa_step_id, references(:qa_steps, type: :uuid, on_delete: :delete_all)
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:qa_screenshots, [:qa_run_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:qa_screenshots, [:qa_step_id])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:qa_screenshots, [:inserted_at])

    create table(:qa_recordings, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :qa_run_id, references(:qa_runs, type: :uuid, on_delete: :delete_all), null: false
      add :started_at, :timestamptz, null: false
      add :duration, :integer, null: false
      timestamps(type: :timestamptz)
    end

    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :qa_app_description, :text, default: "", null: false
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :qa_email, :text, default: "", null: false
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :qa_password, :text, default: "", null: false
    end
  end
end
