defmodule Tuist.Runs.TestModuleRun do
  @moduledoc """
  A test module run represents execution of tests within a specific module/target.
  This is a ClickHouse entity that stores test module run data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :test_run_id,
      :name,
      :status,
      :test_suite_count,
      :test_case_count,
      :avg_test_case_duration,
      :duration
    ],
    sortable: [:inserted_at, :duration, :name, :avg_test_case_duration, :test_case_count, :test_suite_count]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_module_runs" do
    field :name, :string
    field :test_run_id, Ecto.UUID
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :duration, Ch, type: "Int32"
    field :test_suite_count, Ch, type: "Int32"
    field :test_case_count, Ch, type: "Int32"
    field :avg_test_case_duration, Ch, type: "Int32"
    field :inserted_at, Ch, type: "DateTime64(6)"
  end

  def create_changeset(test_module_run, attrs) do
    test_module_run
    |> cast(attrs, [
      :id,
      :name,
      :test_run_id,
      :status,
      :duration,
      :test_suite_count,
      :test_case_count,
      :avg_test_case_duration,
      :inserted_at
    ])
    |> validate_required([
      :id,
      :name,
      :test_run_id,
      :status,
      :duration
    ])
    |> validate_inclusion(:status, ["success", "failure"])
  end
end
