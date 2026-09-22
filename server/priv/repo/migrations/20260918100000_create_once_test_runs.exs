defmodule Tuist.Repo.Migrations.CreateOnceTestRuns do
  use Ecto.Migration

  def change do
    create table(:once_test_suite_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :once_run_id, references(:once_runs, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, :string, size: 128, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      # `target_execution_id` is the once graph target that ran the
      # suite. `suite_id` is a suite-scoped identifier so a target
      # that hosts multiple suites (module test binaries in Rust,
      # multiple XCTest classes, etc.) still gets one row per suite.
      add :target_execution_id, :string, size: 512
      add :suite_id, :string, size: 512

      add :planned_case_count, :integer

      add :total_cases, :integer, default: 0, null: false
      add :passed_cases, :integer, default: 0, null: false
      add :failed_cases, :integer, default: 0, null: false
      add :skipped_cases, :integer, default: 0, null: false
      add :errored_cases, :integer, default: 0, null: false
      add :timed_out_cases, :integer, default: 0, null: false
      add :cancelled_cases, :integer, default: 0, null: false

      add :duration_ms, :bigint, default: 0, null: false
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:once_test_suite_runs, [:once_run_id])
    create index(:once_test_suite_runs, [:project_id, :started_at])

    create unique_index(:once_test_suite_runs, [:once_run_id, :target_execution_id, :suite_id],
             name: :once_test_suite_runs_unique
           )

    create table(:once_test_case_runs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :once_run_id, references(:once_runs, type: :uuid, on_delete: :delete_all), null: false
      add :run_id, :string, size: 128, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      add :target_execution_id, :string, size: 512
      add :suite_id, :string, size: 512

      # `case_id` is the durable per-test identifier the client
      # picks (framework path, XCTest identifier, `crate::mod::name`
      # for Rust). `name` is what a human reads. `class_name` +
      # `module` are optional grouping hints used by the UI to fold
      # rows into tree slices.
      add :case_id, :string, size: 1024, null: false
      add :name, :string, size: 1024, null: false
      add :class_name, :string, size: 512
      add :module, :string, size: 512

      # 1-indexed attempt count so the same case can land multiple
      # times across a run (retries, quarantine reruns).
      add :attempt, :integer, default: 1, null: false

      add :result, :string, size: 32, null: false
      add :duration_ms, :bigint, default: 0, null: false
      add :failure_message, :text
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:once_test_case_runs, [:once_run_id])
    create index(:once_test_case_runs, [:project_id, :started_at])
    create index(:once_test_case_runs, [:project_id, :case_id])

    create unique_index(:once_test_case_runs, [:once_run_id, :case_id, :attempt],
             name: :once_test_case_runs_unique
           )

    alter table(:once_runs) do
      add :test_case_count, :integer, default: 0, null: false
      add :passed_test_cases, :integer, default: 0, null: false
      add :failed_test_cases, :integer, default: 0, null: false
      add :skipped_test_cases, :integer, default: 0, null: false
      add :test_suite_count, :integer, default: 0, null: false
    end
  end
end
