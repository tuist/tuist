defmodule Tuist.Repo.Migrations.CreateGitHistory do
  use Ecto.Migration

  def change do
    create table(:git_commits) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :sha, :string, null: false
      add :object_format, :string, null: false
      add :committed_at, :timestamptz, null: false
      # Git's commit-graph generation number: 1 for a commit whose parents are
      # unknown, 1 + the highest parent generation otherwise. Ancestry walks
      # stop descending below the generation they are looking for.
      add :generation, :integer, null: false
      timestamps(type: :timestamptz)
    end

    create unique_index(:git_commits, [:project_id, :sha])
    create index(:git_commits, [:project_id, :committed_at])

    create table(:git_commit_parents, primary_key: false) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :child_sha, :string, null: false
      add :parent_sha, :string, null: false
      add :position, :integer, null: false
    end

    create unique_index(:git_commit_parents, [:project_id, :child_sha, :position])
    create index(:git_commit_parents, [:project_id, :parent_sha])

    create table(:git_branch_heads, primary_key: false) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :branch, :string, null: false
      add :sha, :string, null: false
      add :seen_at, :timestamptz, null: false
    end

    create unique_index(:git_branch_heads, [:project_id, :branch])

    alter table(:projects) do
      add :git_history_window_days, :integer
      add :git_history_window_commits, :integer
      add :git_history_provider_fallback, :boolean
    end
  end
end
