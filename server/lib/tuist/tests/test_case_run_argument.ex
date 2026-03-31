defmodule Tuist.Tests.TestCaseRunArgument do
  @moduledoc """
  A test case run argument represents a single argument variant of a parameterized test.
  For example, a Swift Testing `@Test(arguments: [...])` or JUnit5 `@ParameterizedTest`
  produces one argument record per argument value.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_run_arguments" do
    field :test_case_run_id, Ecto.UUID
    field :name, :string
    field :status, Ch, type: "LowCardinality(String)"
    field :duration, Ch, type: "Int32"
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_case_run, Tuist.Tests.TestCaseRun,
      foreign_key: :test_case_run_id,
      define_field: false

    has_many :failures, Tuist.Tests.TestCaseFailure, foreign_key: :test_case_run_argument_id
    has_many :repetitions, Tuist.Tests.TestCaseRunRepetition, foreign_key: :test_case_run_argument_id
    has_many :attachments, Tuist.Tests.TestCaseRunAttachment, foreign_key: :test_case_run_argument_id
  end

  def create_changeset(argument, attrs) do
    argument
    |> cast(attrs, [:id, :test_case_run_id, :name, :status, :duration, :inserted_at])
    |> validate_required([:id, :test_case_run_id, :name, :status])
    |> validate_inclusion(:status, ["success", "failure"])
  end
end
