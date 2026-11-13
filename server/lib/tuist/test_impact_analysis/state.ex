defmodule Tuist.TestImpactAnalysis.State do
  @moduledoc """
  The decisions the rules have made so far, by test case id. A test without
  one is undecided. A decision is final: selecting or skipping a decided test
  changes nothing, so the first rule that decides a test gives its reason.
  """
  defstruct decisions: %{}

  def new, do: %__MODULE__{}

  @doc "Whether the test is still undecided."
  def undecided?(%__MODULE__{decisions: decisions}, test_case_id), do: not Map.has_key?(decisions, test_case_id)

  @doc "The given tests (anything with a `test_case_id`) still undecided."
  def undecided(%__MODULE__{} = state, tests), do: Enum.filter(tests, &undecided?(state, &1.test_case_id))

  @doc "Selects an undecided test with the rule's reason and, optionally, the path that made it run."
  def select(%__MODULE__{} = state, test_case_id, reason, matched_path \\ nil),
    do: decide(state, test_case_id, %{decision: :selected, reason: reason, matched_path: matched_path})

  @doc "Skips an undecided test with the rule's reason."
  def skip(%__MODULE__{} = state, test_case_id, reason),
    do: decide(state, test_case_id, %{decision: :skipped, reason: reason, matched_path: nil})

  @doc "How many tests `next` selected and skipped that `state` left undecided, as `{selected, skipped}`."
  def added(%__MODULE__{decisions: before}, %__MODULE__{decisions: decisions}) do
    decisions
    |> Enum.reject(fn {test_case_id, _decision} -> Map.has_key?(before, test_case_id) end)
    |> Enum.reduce({0, 0}, fn
      {_id, %{decision: :selected}}, {selected, skipped} -> {selected + 1, skipped}
      {_id, %{decision: :skipped}}, {selected, skipped} -> {selected, skipped + 1}
    end)
  end

  defp decide(%__MODULE__{decisions: decisions} = state, test_case_id, decision),
    do: %{state | decisions: Map.put_new(decisions, test_case_id, decision)}
end
