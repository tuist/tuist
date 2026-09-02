defmodule Tuist.Tests.TestRunStressCandidate do
  @moduledoc """
  One test case the stress gate examined for a test run: the identity the run
  reported, how many repetitions the project's curve priced it at, how many
  failed, and the outcome the gate assigned. Stored in ClickHouse beside the
  `Tuist.Tests.Test` it belongs to via `test_run_id`, apart from
  `test_case_run_repetitions`, so the flakiness aggregates, auto-marking and
  alerts never read a solicited repetition as an organic one.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @outcomes ~w(passed disagreed excluded_too_slow excluded_candidate_cap not_stressed_ceiling not_stressed_error)

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_run_stress_candidates" do
    field :test_run_id, Ecto.UUID
    field :project_id, Ch, type: "Int64"
    field :test_case_id, Ecto.UUID
    field :name, Ch, type: "String"
    field :suite_name, Ch, type: "String"
    field :module_name, Ch, type: "String"
    field :repetitions, Ch, type: "UInt16"
    field :failed_repetitions, Ch, type: "UInt16"
    field :outcome, Ch, type: "LowCardinality(String)"
    field :is_quarantined, :boolean, default: false
    field :inserted_at, Ch, type: "DateTime64(6)"

    belongs_to :test_run, Tuist.Tests.Test, foreign_key: :test_run_id, define_field: false
  end

  def outcomes, do: @outcomes

  def create_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :id,
      :test_run_id,
      :project_id,
      :test_case_id,
      :name,
      :suite_name,
      :module_name,
      :repetitions,
      :failed_repetitions,
      :outcome,
      :is_quarantined,
      :inserted_at
    ])
    |> validate_required([:id, :test_run_id, :project_id, :test_case_id, :name, :module_name, :outcome])
    |> validate_inclusion(:outcome, @outcomes)
  end
end
