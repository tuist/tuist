defmodule Tuist.Repo.Migrations.CreateTestImpactSnapshots do
  @moduledoc """
  `test_impact_snapshots`: the index of coverage-based test selection's test
  maps (`Tuist.TestImpactAnalysis.Snapshots`), one row per snapshot. The
  maps themselves live in ClickHouse (`test_impact_snapshot_tests` and
  `test_impact_snapshot_files`) under the row's id.

  A `checkpoint` is written from a commit's full runs of a scope
  (repository, scheme, platform), and again when another full run of it
  arrives; readers take the newest, and the earlier ones stay for the
  overlays written against them until they expire. An
  `overlay` is written from a run that had an impact run, against the
  checkpoint at that impact run's baseline (`checkpoint_id`, `base_sha`),
  and keyed by the commit the impact run checked out, which is GitHub's
  merge commit on a pull request's merge checkout.

  Rows expire with their maps, 31 days after the run.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:test_impact_snapshots, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :repository_id, :bigint, null: false
      add :commit_sha, :string, null: false
      add :kind, :string, null: false
      add :checkpoint_id, :uuid
      add :base_sha, :string
      add :scheme, :string, null: false, default: ""
      add :platform, :string, null: false, default: ""
      add :git_branch, :string, null: false, default: ""
      add :test_run_ids, {:array, :uuid}, null: false, default: []
      add :test_impact_run_id, :uuid
      add :tests_count, :integer, null: false, default: 0
      add :overridden_count, :integer, null: false, default: 0
      add :ran_at, :timestamptz, null: false
      add :expires_at, :timestamptz, null: false
      timestamps(type: :timestamptz, updated_at: false)
    end

    create index(:test_impact_snapshots, [:project_id, :commit_sha], concurrently: true)
    create index(:test_impact_snapshots, [:project_id, :git_branch, :ran_at], concurrently: true)
    create index(:test_impact_snapshots, [:expires_at], concurrently: true)
  end
end
