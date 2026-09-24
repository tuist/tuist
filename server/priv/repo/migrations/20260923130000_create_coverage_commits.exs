defmodule Tuist.Repo.Migrations.CreateCoverageCommits do
  @moduledoc """
  A commit's coverage within a project (`Tuist.Tests.CoverageCommit`): the
  totals over the union of its runs, what a comparison, a branch's history and
  a pull request's gate read. It lives beside the commit graph so a branch's
  commits and a baseline are range queries on the ref's positions, and it
  outlives both the graph's window and the per-file detail in ClickHouse: the
  ref, position and commit date are copies.
  """
  use Ecto.Migration

  def change do
    create table(:coverage_commits, primary_key: false) do
      add :project_id, references(:projects, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :git_commit_sha, :string, null: false, primary_key: true
      add :repository_id, references(:git_repositories, on_delete: :nilify_all)
      add :ref_id, references(:git_refs, on_delete: :nilify_all)
      add :position, :integer
      add :committed_at, :timestamptz, null: false
      add :build_system, :string, null: false, default: "xcode"
      # What the commit's newest run reported: its branch, the pull request of
      # its newest pull request run, and when it last ran.
      add :git_branch, :string, null: false, default: ""
      add :pull_request_number, :integer, null: false, default: 0
      add :base_branch, :string, null: false, default: ""
      add :ran_at, :timestamptz, null: false
      add :covered_lines, :bigint, null: false, default: 0
      add :executable_lines, :bigint, null: false, default: 0
      add :measured_files_count, :integer, null: false, default: 0
      add :unmeasured_files_count, :integer, null: false, default: 0
      add :schemes, {:array, :string}, null: false, default: []
      add :partial_schemes, {:array, :string}, null: false, default: []
      add :test_run_ids, {:array, :uuid}, null: false, default: []
      add :complete, :boolean, null: false, default: false
      add :completeness, :string, null: false, default: ""
      add :reported_covered_lines, :bigint, null: false, default: 0
      add :reported_executable_lines, :bigint, null: false, default: 0
      add :reported_kind, :string, null: false, default: ""
      add :skipped_tests_count, :integer, null: false, default: 0
      add :carried_tests_count, :integer, null: false, default: 0
      add :gap_files_count, :integer, null: false, default: 0
      add :carried_from, {:array, :string}, null: false, default: []
      # Bumped on every fold, so what is cached per published version expires.
      add :version, :bigint, null: false, default: 1
      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:coverage_commits, [:project_id, :ref_id, :position])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:coverage_commits, [:project_id, :ref_id, :committed_at])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:coverage_commits, [:project_id, :git_branch, :ran_at])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:coverage_commits, [:project_id, :pull_request_number],
             where: "pull_request_number > 0"
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:coverage_commits, [:project_id, :ran_at])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:coverage_commits, [:repository_id, :git_commit_sha])
  end
end
