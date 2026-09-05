defmodule Tuist.Repo.Migrations.CreateBazelTestResults do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:bazel_test_invocations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, :bigint, null: false
      add :invocation_id, :string, null: false
      add :state, :string, null: false, default: "collecting"
      add :test_run_id, :uuid, null: false
      add :artifact_bytes, :bigint, null: false, default: 0

      timestamps(type: :timestamptz)
    end

    # The table is new and empty, so adding this constraint cannot block existing writes.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:bazel_test_invocations, :bazel_test_invocations_artifact_bytes_bound,
             check: "artifact_bytes >= 0 AND artifact_bytes <= 67108864"
           )

    create unique_index(
             :bazel_test_invocations,
             [:project_id, :invocation_id],
             name: :bazel_test_invocations_identity_index,
             concurrently: true
           )

    create index(:bazel_test_invocations, [:inserted_at, :id], concurrently: true)

    create table(:bazel_test_results, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, :bigint, null: false
      add :invocation_id, :string, null: false
      add :target_label, :text, null: false
      add :run, :integer, null: false
      add :shard, :integer, null: false
      add :attempt, :integer, null: false
      add :status, :string, null: false
      add :duration_ms, :bigint, null: false
      add :started_at, :timestamptz, null: false
      add :cached, :boolean, null: false
      add :is_ci, :boolean, null: false
      add :sequence_number, :bigint, null: false
      add :junit_digest, :string
      add :junit_content, :binary
      add :log_digest, :string
      add :log_content, :binary

      timestamps(type: :timestamptz)
    end

    create unique_index(
             :bazel_test_results,
             [:project_id, :invocation_id, :target_label, :run, :shard, :attempt],
             name: :bazel_test_results_identity_index,
             concurrently: true
           )

    create index(:bazel_test_results, [:inserted_at, :id], concurrently: true)

    create table(:bazel_test_summaries, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :project_id, :bigint, null: false
      add :invocation_id, :string, null: false
      add :target_label, :text, null: false
      add :status, :string, null: false
      add :total_run_count, :integer, null: false
      add :total_num_cached, :integer, null: false
      add :duration_ms, :bigint, null: false
      add :started_at, :timestamptz, null: false
      add :finished_at, :timestamptz, null: false

      timestamps(type: :timestamptz)
    end

    create unique_index(
             :bazel_test_summaries,
             [:project_id, :invocation_id, :target_label],
             name: :bazel_test_summaries_identity_index,
             concurrently: true
           )

    create index(:bazel_test_summaries, [:inserted_at, :id], concurrently: true)
  end
end
