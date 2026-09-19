defmodule Tuist.Repo.Migrations.CreateGitHistory do
  @moduledoc """
  The commit graph coverage comparisons walk, keyed by repository rather than
  by project: several projects can point at one repository (a monorepo with
  more than one Tuist project) and one project's runs may come from a fork,
  so the graph belongs to the repository the run's remote names, scoped to
  the account. `git_commit_listings` records which commits have their file
  listing in ClickHouse (`git_commit_files`), so a client only uploads a
  listing the server lacks.
  """
  use Ecto.Migration

  def change do
    create table(:git_repositories) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      # The normalized remote: host, owner and name, lowercased, without the
      # scheme, credentials or `.git`.
      add :key, :string, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:git_repositories, [:account_id, :key])

    create table(:git_commits) do
      add :repository_id, references(:git_repositories, on_delete: :delete_all), null: false
      add :sha, :string, null: false
      add :object_format, :string, null: false
      add :committed_at, :timestamptz, null: false
      # Git's commit-graph generation number: 1 for a commit whose parents are
      # unknown, 1 + the highest parent generation otherwise. Ancestry walks
      # stop descending below the generation they are looking for.
      add :generation, :integer, null: false
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:git_commits, [:repository_id, :sha])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:git_commits, [:repository_id, :committed_at])

    create table(:git_commit_parents, primary_key: false) do
      add :repository_id, references(:git_repositories, on_delete: :delete_all), null: false
      add :child_sha, :string, null: false
      add :parent_sha, :string, null: false
      add :position, :integer, null: false
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:git_commit_parents, [:repository_id, :child_sha, :position])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:git_commit_parents, [:repository_id, :parent_sha])

    create table(:git_branch_heads, primary_key: false) do
      add :repository_id, references(:git_repositories, on_delete: :delete_all), null: false
      add :branch, :string, null: false
      add :sha, :string, null: false
      add :seen_at, :timestamptz, null: false
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:git_branch_heads, [:repository_id, :branch])

    create table(:git_commit_listings, primary_key: false) do
      add :repository_id, references(:git_repositories, on_delete: :delete_all), null: false
      add :sha, :string, null: false
      add :files_count, :integer, null: false
      add :truncated, :boolean, null: false, default: false
      add :inserted_at, :timestamptz, null: false
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:git_commit_listings, [:repository_id, :sha])

    alter table(:projects) do
      add :git_history_window_days, :integer
      add :git_history_window_commits, :integer
    end
  end
end
