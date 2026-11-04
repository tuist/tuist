defmodule Tuist.TestImpactAnalysis do
  @moduledoc """
  Coverage-based test selection: which of the tests in scope a run can skip
  because nothing they executed at the baseline changed.

  Selection is a pipeline of rules (`Tuist.TestImpactAnalysis.Rule`) run in a
  fixed order over one shared input (`Tuist.TestImpactAnalysis.Input`). Every
  test starts undecided; a rule can select or skip an undecided test, and a
  decided test is final, so the first rule that decides a test gives its
  reason. Each rule returns a verdict:

  - `:continue` runs the next rule;
  - `:done` stops the pipeline and keeps the decisions so far;
  - `{:abort, reason, matched_path}` says selection can't happen: every
    decision is discarded and the outcome is `:fallback`, after which the
    client runs default selective testing.

  Tests still undecided when the pipeline stops are selected as
  `:undecided`, so a missing rule or an early `:done` can only select more.

  The rules are pure: they read the input and return decisions, with no
  writes and no reads of their own. The order is code, versioned by
  `rules_version/0`, and every run leaves a trace of what each rule decided.
  """
  alias Tuist.TestImpactAnalysis.Input
  alias Tuist.TestImpactAnalysis.Rules
  alias Tuist.TestImpactAnalysis.State

  # Bump when a rule's behaviour or the order changes, so a stored decision
  # can be traced to the rules that made it.
  @rules_version "1"

  @rules [
    Rules.TrackedFiles,
    Rules.TestFileChanged,
    Rules.FailedLastRun,
    Rules.NoEvidence,
    Rules.Impacted,
    Rules.OwnedWithoutEvidence,
    Rules.Unaffected
  ]

  @doc "The version of the rule list `run/1` applies."
  def rules_version, do: @rules_version

  @doc "The rules `run/1` applies, in order."
  def rules, do: @rules

  @doc """
  Applies the rules to the input and returns the decision:

  - `outcome`: `:selected`, or `:fallback` when a rule aborted;
  - `reason` and `matched_path`: why it fell back, and the file that caused
    it; nil when selected;
  - `decisions`: `%{test_case_id => %{decision: :selected | :skipped,
    reason:, matched_path:}}` for every test in scope, empty on a fallback;
  - `counts`: tests `requested`, `selected` and `skipped`, zero on a
    fallback but for `requested`;
  - `rules_version` and `rule_trace`, one `%{rule:, selected:, skipped:,
    verdict:}` per rule that ran, in order; the last names the rule that
    aborted or finished.

  `rules` replaces the rule list, for tests.
  """
  def run(%Input{} = input, rules \\ @rules) do
    {state, trace, verdict} =
      Enum.reduce_while(rules, {State.new(), [], :continue}, fn rule, {state, trace, _verdict} ->
        {next, verdict} = rule.decide(input, state)
        {selected, skipped} = State.added(state, next)
        trace = [%{rule: rule.name(), selected: selected, skipped: skipped, verdict: verdict_name(verdict)} | trace]

        case verdict do
          :continue -> {:cont, {next, trace, verdict}}
          _halt -> {:halt, {next, trace, verdict}}
        end
      end)

    result(input, state, Enum.reverse(trace), verdict)
  end

  defp result(input, _state, trace, {:abort, reason, matched_path}) do
    %{
      outcome: :fallback,
      reason: reason,
      matched_path: matched_path,
      decisions: %{},
      counts: %{requested: length(input.tests), selected: 0, skipped: 0},
      rules_version: @rules_version,
      rule_trace: trace
    }
  end

  defp result(input, state, trace, _verdict) do
    state = Enum.reduce(State.undecided(state, input.tests), state, &State.select(&2, &1.test_case_id, :undecided))
    decisions = state.decisions

    %{
      outcome: :selected,
      reason: nil,
      matched_path: nil,
      decisions: decisions,
      counts: %{
        requested: length(input.tests),
        selected: Enum.count(decisions, fn {_id, d} -> d.decision == :selected end),
        skipped: Enum.count(decisions, fn {_id, d} -> d.decision == :skipped end)
      },
      rules_version: @rules_version,
      rule_trace: trace
    }
  end

  defp verdict_name({:abort, _reason, _matched_path}), do: :abort
  defp verdict_name(verdict), do: verdict
end
