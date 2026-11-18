defmodule Tuist.Repo.Migrations.CreateSnapshots do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:snapshot_builds, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :set_name, :string, null: false
      add :git_commit_sha, :string
      add :git_branch, :string
      add :git_ref, :string
      add :git_remote_url_origin, :string
      add :merge_base_sha, :string
      add :pull_request_number, :integer
      add :pull_request_title, :text
      add :is_ci, :boolean, null: false, default: false
      add :build_system, :string
      add :state, :string, null: false, default: "uploading"
      add :baseline_build_id, references(:snapshot_builds, type: :uuid, on_delete: :nilify_all)
      add :unchanged_count, :integer, null: false, default: 0
      add :changed_count, :integer, null: false, default: 0
      add :added_count, :integer, null: false, default: 0
      add :removed_count, :integer, null: false, default: 0
      # Removed images whose content reappeared under another name.
      add :renamed_count, :integer, null: false, default: 0
      # Images a selective run didn't render, carried over from the baseline.
      add :skipped_count, :integer, null: false, default: 0
      add :selective, :boolean, null: false, default: false
      add :approved_at, :timestamptz
      add :approved_by_account_id, references(:accounts, on_delete: :nilify_all)
      add :processed_at, :timestamptz
      # A digest of what the comparison found to review (each changed or
      # removed image's name, baseline and new content), so a later build on
      # the same branch with exactly the same changes inherits an approval.
      add :changes_signature, :string
      add :approved_by_github_handle, :string
      add :rejected_at, :timestamptz
      add :rejected_by_account_id, references(:accounts, on_delete: :nilify_all)
      add :rejected_by_github_handle, :string

      add :approved_from_build_id,
          references(:snapshot_builds, type: :uuid, on_delete: :nilify_all)

      add :github_check_run_id, :bigint
      timestamps(type: :timestamptz)
    end

    create index(:snapshot_builds, [:project_id, :set_name, :git_commit_sha], concurrently: true)

    # Finding an approved build with the same changes filters on all four columns.
    # excellent_migrations:safety-assured-for-next-line many_columns_index
    create index(:snapshot_builds, [:project_id, :set_name, :git_branch, :changes_signature],
             name: :snapshot_builds_changes_signature_index,
             concurrently: true
           )

    create index(:snapshot_builds, [:project_id, :inserted_at], concurrently: true)

    create table(:snapshot_images, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :build_id, references(:snapshot_builds, type: :uuid, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :content_hash, :string
      add :width, :integer
      add :height, :integer
      add :test_identifier, :string
      # From the image's JSON sidecar (Sentry's format): how the review page
      # names, groups and tags it, and the share of pixels that may differ
      # before it counts as changed.
      add :display_name, :string
      add :group, :string
      add :tags, :map, null: false, default: %{}
      add :diff_threshold, :float
      add :status, :string
      add :baseline_content_hash, :string
      add :baseline_width, :integer
      add :baseline_height, :integer
      add :diff_ratio, :float
      add :diff_key, :string
      add :renamed_from, :string
      timestamps(type: :timestamptz)
    end

    create unique_index(:snapshot_images, [:build_id, :name], concurrently: true)
    create index(:snapshot_images, [:content_hash], concurrently: true)

    # One row per commit, republished from its builds whenever one changes
    # (like `coverage_commits`), so the dashboard lists commits rather than
    # uploads. `completed_at` is the commit's completion signal, shared with
    # coverage (`tuist coverage complete`).
    create table(:snapshot_commits, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :git_commit_sha, :string, null: false
      add :git_branch, :string
      add :pull_request_number, :integer
      add :pull_request_title, :text
      add :status, :string, null: false, default: "processing"
      add :unchanged_count, :integer, null: false, default: 0
      add :changed_count, :integer, null: false, default: 0
      add :added_count, :integer, null: false, default: 0
      add :removed_count, :integer, null: false, default: 0
      add :renamed_count, :integer, null: false, default: 0
      add :skipped_count, :integer, null: false, default: 0
      add :runs_count, :integer, null: false, default: 0
      add :set_names, {:array, :string}, null: false, default: []
      add :baseline_commit_sha, :string
      add :baseline_git_branch, :string
      add :approved_at, :timestamptz
      add :approved_by_account_id, references(:accounts, on_delete: :nilify_all)
      add :approved_by_github_handle, :string
      add :rejected_at, :timestamptz
      add :rejected_by_account_id, references(:accounts, on_delete: :nilify_all)
      add :rejected_by_github_handle, :string
      add :completed_at, :timestamptz
      add :last_uploaded_at, :timestamptz
      timestamps(type: :timestamptz)
    end

    create unique_index(:snapshot_commits, [:project_id, :git_commit_sha], concurrently: true)
  end
end
