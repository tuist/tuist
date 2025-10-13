defmodule Tuist.Runs.TestSuiteRun do
  @moduledoc """
  A test suite run represents execution of a test suite within a module.
  This is a ClickHouse entity that stores test suite run data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :test_run_id,
      :test_module_run_id,
      :name,
      :status
    ],
    sortable: [:inserted_at, :duration]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_suite_runs" do
    field :name, :string
    field :test_run_id, Ecto.UUID
    field :test_module_run_id, Ecto.UUID
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :duration, Ch, type: "Int32"
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
      :duration,
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
    |> validate_inclusion(:status, [0, 1, 2, :success, :failure, :skipped])
  end
end