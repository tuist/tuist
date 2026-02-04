defmodule Tuist.Tests.TestCaseRunRepetition do
  @moduledoc """
  A test case run repetition represents a single execution attempt of a test case.
  When tests are run with retry-on-failure, each attempt is stored as a repetition.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_run_repetitions" do
    field :test_case_run_id, Ecto.UUID
    field :repetition_number, Ch, type: "Int32"
    field :name, :string
    field :status, Ch, type: "LowCardinality(String)"
    field :duration, Ch, type: "Int32"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_case_run, Tuist.Tests.TestCaseRun,
      foreign_key: :test_case_run_id,
      define_field: false
  end

  def create_changeset(repetition, attrs) do
    repetition
    |> cast(attrs, [:id, :test_case_run_id, :repetition_number, :name, :status, :duration, :inserted_at])
    |> validate_required([:id, :test_case_run_id, :repetition_number, :name, :status])
    |> validate_inclusion(:status, ["success", "failure"])
  end
end
