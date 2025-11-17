defmodule Tuist.Runs.TestCaseRun do
  @moduledoc """
  A test case run represents execution of a single test case.
  This is a ClickHouse entity that stores test case run data.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [
      :test_run_id,
      :test_module_run_id,
      :test_suite_run_id,
      :name,
      :status
    ],
    sortable: [:inserted_at, :duration, :name]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_runs" do
    field :name, :string
    field :test_run_id, Ecto.UUID
    field :test_module_run_id, Ecto.UUID
    field :test_suite_run_id, Ecto.UUID
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :duration, Ch, type: "Int32"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :module_name, Ch, type: "String"
    field :suite_name, Ch, type: "String"
  end

  def create_changeset(test_case_run, attrs) do
    test_case_run
    |> cast(attrs, [
      :id,
      :name,
      :test_run_id,
      :test_module_run_id,
      :test_suite_run_id,
      :status,
      :duration,
      :inserted_at,
      :module_name,
      :suite_name
    ])
    |> validate_required([
      :id,
      :name,
      :test_run_id,
      :test_module_run_id,
      :status,
      :duration,
      :module_name,
      :suite_name
    ])
    |> validate_inclusion(:status, [0, 1, 2, :success, :failure, :skipped])
  end

  def normalize_enums(test_case_run) do
    %{
      test_case_run
      | status: status_int_to_atom(test_case_run.status)
    }
  end

  defp status_int_to_atom(0), do: :success
  defp status_int_to_atom(1), do: :failure
  defp status_int_to_atom(2), do: :skipped
  defp status_int_to_atom("success"), do: :success
  defp status_int_to_atom("failure"), do: :failure
  defp status_int_to_atom("skipped"), do: :skipped
  defp status_int_to_atom(atom) when is_atom(atom), do: atom
end
