defmodule Tuist.TestImpactAnalysis do
  @moduledoc """
  Coverage-based test selection: which of the tests in scope a run can skip
  because nothing they executed at the baseline changed.

  The baseline is the nearest ancestor with a checkpoint of the scope
  (`Tuist.TestImpactAnalysis.Baselines`). A changed tracked file runs every
  test (`tracked_file_changed`, `Tuist.TestImpactAnalysis.TrackedFiles`). Otherwise each test of the checkpoint gets
  the reason of the first rule that decides it, in this order
  (`Tuist.TestImpactAnalysis.Candidate`, combined across candidates by
  `Tuist.TestImpactAnalysis.Decision`):

  1. `test_file_changed`: a changed test file belongs to its suite;
  2. `failed_last_run`: it failed or was flaky where its files are unchanged;
  3. `no_evidence`: it has no evidence of its own, or it's `stale`;
  4. `impacted`: a file it, its suite's setup or its module's processes
     executed changed;
  5. `unaffected`: skipped.

  A changed file that no evidence includes and no tracked pattern matches
  selects nothing.

  The order is code, versioned by `rules_version/0`, and every run records
  how many tests each rule decided (`rule_trace/1`).
  """

  # Bump when a rule's behaviour or the order changes, so a stored decision
  # can be traced to the rules that made it.
  @rules_version "4"

  @reasons [:test_file_changed, :failed_last_run, :no_evidence, :impacted, :unaffected]

  @doc "The version of the rules that decide a run."
  def rules_version, do: @rules_version

  @doc "Why a test is decided, in the rules' order."
  def reasons, do: @reasons

  @doc """
  The trace of a decision (`Decision.decide/4`): one `%{rule:, selected:,
  skipped:, verdict:}` per rule in order, the last one `done`.
  """
  def rule_trace(decisions) do
    counts = decisions |> Map.values() |> Enum.frequencies_by(&{&1.reason, &1.decision})
    last = length(@reasons) - 1

    @reasons
    |> Enum.with_index()
    |> Enum.map(fn {reason, i} ->
      %{
        rule: to_string(reason),
        selected: Map.get(counts, {reason, :selected}, 0),
        skipped: Map.get(counts, {reason, :skipped}, 0),
        verdict: if(i == last, do: "done", else: "continue")
      }
    end)
  end

  @doc "The trace of a run every test of which runs because a tracked file changed."
  def tracked_trace, do: [%{rule: "tracked_files", selected: 0, skipped: 0, verdict: "abort"}]
end
