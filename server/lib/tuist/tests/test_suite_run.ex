defmodule Tuist.Tests.TestSuiteRun do
  @moduledoc """
  A test suite run represents execution of a test suite within a module.
  This is a ClickHouse entity that stores test suite run data.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :test_run_id,
      :test_module_run_id,
      :shard_id,
      :shard_index,
      :name,
      :status,
      :test_case_count,
      :avg_test_case_duration,
      :duration
    ],
    sortable: [:inserted_at, :duration, :name, :avg_test_case_duration, :test_case_count]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_suite_runs" do
    field :name, Ch, type: "String"
    field :test_run_id, Ecto.UUID
    field :test_module_run_id, Ecto.UUID
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :is_flaky, :boolean, default: false
    field :duration, Ch, type: "Int32"
    field :test_case_count, Ch, type: "Int32"
    field :avg_test_case_duration, Ch, type: "Int32"
    field :shard_id, Ch, type: "Nullable(UUID)"
    field :shard_index, Ch, type: "Nullable(Int32)"
    field :project_id, Ch, type: "Nullable(Int64)"
    field :is_ci, :boolean, default: false
    field :git_branch, Ch, type: "String", default: ""
    field :ran_at, Ch, type: "Nullable(DateTime64(6))"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(test_suite_run, attrs) do
    test_suite_run
    |> cast(attrs, [
      :id,
      :name,
      :test_run_id,
      :test_module_run_id,
      :status,
      :is_flaky,
      :duration,
      :test_case_count,
      :avg_test_case_duration,
      :shard_id,
      :shard_index,
      :project_id,
      :is_ci,
      :git_branch,
      :ran_at,
      :inserted_at
    ])
    |> validate_required([
      :id,
      :name,
      :test_run_id,
      :test_module_run_id,
      :status,
      :duration
    ])
    |> validate_inclusion(:status, ["success", "failure", "skipped"])
  end
end
