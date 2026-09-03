defmodule Tuist.Tests.TestRunStressRepetition do
  @moduledoc """
  One execution of a test case during the stress gate's pass, in order, with the
  failure it produced when it failed.

  Kept apart from `test_case_run_repetitions` on purpose: these repetitions were
  solicited by the gate rather than observed in the wild, and everything that
  attributes flakiness to a test case reads that table. The dashboard reads this
  one to render the gate's findings like any other failure.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(success failure)

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_run_stress_repetitions" do
    field :test_run_id, Ecto.UUID
    field :project_id, Ch, type: "Int64"
    field :test_case_id, Ecto.UUID
    field :repetition_number, Ch, type: "UInt16"
    field :status, Ch, type: "LowCardinality(String)"
    field :duration, Ch, type: "Int32"
    field :failure_message, Ch, type: "String"
    field :failure_path, Ch, type: "String"
    field :failure_line_number, Ch, type: "Int32"
    field :failure_issue_type, Ch, type: "LowCardinality(String)"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_run, Tuist.Tests.Test, foreign_key: :test_run_id, define_field: false
  end

  def statuses, do: @statuses

  @doc """
  The failure this repetition produced, shaped like a `Tuist.Tests.TestCaseFailure`
  so the dashboard renders it through the same component. Nil when it passed.
  """
  def failure(%__MODULE__{status: "failure"} = repetition) do
    %{
      message: presence(repetition.failure_message),
      path: presence(repetition.failure_path),
      line_number: repetition.failure_line_number,
      issue_type: presence(repetition.failure_issue_type)
    }
  end

  def failure(_), do: nil

  defp presence(""), do: nil
  defp presence(value), do: value

  def create_changeset(repetition, attrs) do
    repetition
    |> cast(attrs, [
      :id,
      :test_run_id,
      :project_id,
      :test_case_id,
      :repetition_number,
      :status,
      :duration,
      :failure_message,
      :failure_path,
      :failure_line_number,
      :failure_issue_type,
      :inserted_at
    ])
    |> validate_required([:id, :test_run_id, :project_id, :test_case_id, :repetition_number, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
