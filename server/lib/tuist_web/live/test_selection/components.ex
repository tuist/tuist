defmodule TuistWeb.TestSelection.Components do
  @moduledoc """
  The cells and words test selection shares across the Test Selection page,
  a test run's Selective Testing tab and a test case run's Selective
  Testing tab: a decision as a badge, the reasons behind it, a test's
  outcome, why an impact run fell back to default selective testing, and how
  a changed file changed.
  """
  use TuistWeb, :html
  use Noora

  attr :decision, :string, required: true

  def decision_cell(assigns) do
    ~H"""
    <.badge_cell
      label={decision_label(@decision)}
      color={decision_color(@decision)}
      icon={decision_icon(@decision)}
      style="light-fill"
    />
    """
  end

  attr :decision, :string, required: true
  attr :size, :string, default: "large"

  def decision_badge(assigns) do
    ~H"""
    <.badge
      label={decision_label(@decision)}
      color={decision_color(@decision)}
      style="light-fill"
      size={@size}
    >
      <:icon><.icon name={decision_icon(@decision)} /></:icon>
    </.badge>
    """
  end

  def decision_label("selected"), do: dgettext("dashboard_tests", "Selected")
  def decision_label("skipped"), do: dgettext("dashboard_tests", "Skipped")
  def decision_label(_decision), do: dgettext("dashboard_tests", "Unknown")

  defp decision_color("selected"), do: "primary"
  defp decision_color(_decision), do: "neutral"

  defp decision_icon("selected"), do: "player_play"
  defp decision_icon(_decision), do: "player_track_next"

  @doc "A test's reason, short enough for a table cell: the rule that decided it."
  def reason_label("test_file_changed"), do: dgettext("dashboard_tests", "Its test file changed")
  def reason_label("failed_last_run"), do: dgettext("dashboard_tests", "Failed last run")
  def reason_label("no_evidence"), do: dgettext("dashboard_tests", "No evidence")
  def reason_label("impacted"), do: dgettext("dashboard_tests", "Executes a changed file")
  def reason_label("owned_without_evidence"), do: dgettext("dashboard_tests", "Its module changed")
  def reason_label("undecided"), do: dgettext("dashboard_tests", "Undecided")
  def reason_label("unaffected"), do: dgettext("dashboard_tests", "No executed file changed")
  def reason_label("unchanged_module"), do: dgettext("dashboard_tests", "Its module is unchanged")
  def reason_label(reason), do: reason

  @doc "A test's reason, as the sentence its page explains it with."
  def reason_description("test_file_changed", path),
    do:
      dgettext(
        "dashboard_tests",
        "%{path} is test code of its suite and changed since the baseline, so every test of the suite runs.", path: path)

  def reason_description("failed_last_run", _path),
    do:
      dgettext(
        "dashboard_tests",
        "Its newest run in the evidence window failed or flaked, so a past pass can't vouch for it."
      )

  def reason_description("no_evidence", _path),
    do:
      dgettext(
        "dashboard_tests",
        "No run in the evidence window recorded coverage evidence of its own for it (it is new, it is a Swift Testing test, or its target doesn't link TestCoverageAttribution), so Tuist can't tell what it depends on."
      )

  def reason_description("impacted", path),
    do:
      dgettext("dashboard_tests", "Its evidence shows it executed %{path}, which changed since, so it has to run again.",
        path: path
      )

  def reason_description("owned_without_evidence", path),
    do:
      dgettext(
        "dashboard_tests",
        "%{path} changed, no evidence includes it (a resource, a new file or one with only declarations), and its module can affect this test's module, so every test there runs.",
        path: path
      )

  def reason_description("undecided", _path),
    do: dgettext("dashboard_tests", "No rule decided it, so it runs: selection only skips what a rule proves unaffected.")

  def reason_description("unaffected", _path),
    do:
      dgettext(
        "dashboard_tests",
        "It passed in the baseline and none of the files it executed changed since, so running it again is not expected to add signal."
      )

  def reason_description("unchanged_module", _path),
    do:
      dgettext(
        "dashboard_tests",
        "Selective testing found its module unchanged since a passing run, so the module was skipped before coverage decided anything."
      )

  def reason_description(reason, _path), do: reason

  @doc "Why an impact run fell back to default selective testing."
  def fallback_label("no_baseline"), do: dgettext("dashboard_tests", "No baseline")
  def fallback_label("baseline_too_old"), do: dgettext("dashboard_tests", "Baseline too far back")
  def fallback_label("no_baseline_evidence"), do: dgettext("dashboard_tests", "No baseline evidence")
  def fallback_label("history_unavailable"), do: dgettext("dashboard_tests", "History too shallow")
  def fallback_label("tracked_file_changed"), do: dgettext("dashboard_tests", "Tracked file changed")
  def fallback_label("diff_too_large"), do: dgettext("dashboard_tests", "Diff too large")
  def fallback_label("diff_unavailable"), do: dgettext("dashboard_tests", "Diff unavailable")
  def fallback_label("history_unknown"), do: dgettext("dashboard_tests", "Commit unknown")
  def fallback_label(reason), do: reason

  def fallback_description("no_baseline"),
    do:
      dgettext(
        "dashboard_tests",
        "No ancestor of this commit has a complete full run with per-test evidence for the requested scope."
      )

  def fallback_description("baseline_too_old"),
    do: dgettext("dashboard_tests", "The nearest baseline is more than 20 measured commits back.")

  def fallback_description("no_baseline_evidence"),
    do: dgettext("dashboard_tests", "The baseline recorded no per-test coverage evidence.")

  def fallback_description("history_unavailable"),
    do: dgettext("dashboard_tests", "The CLI couldn't fetch enough history to diff against the baseline in time.")

  def fallback_description("tracked_file_changed"),
    do:
      dgettext(
        "dashboard_tests",
        "A file that can affect any test without showing up in coverage changed, such as a dependency pin or build settings."
      )

  def fallback_description("diff_too_large"),
    do: dgettext("dashboard_tests", "More than 5,000 files changed since the baseline.")

  def fallback_description("diff_unavailable"),
    do: dgettext("dashboard_tests", "The changed files since the baseline couldn't be read.")

  def fallback_description("history_unknown"),
    do:
      dgettext(
        "dashboard_tests",
        "Tuist's commit history has neither the checked-out commit nor its parents, so it couldn't look for a baseline."
      )

  def fallback_description(reason), do: reason

  def file_status_label("added"), do: dgettext("dashboard_tests", "Added")
  def file_status_label("deleted"), do: dgettext("dashboard_tests", "Deleted")
  def file_status_label(_status), do: dgettext("dashboard_tests", "Modified")

  def file_status(status) when status in ["added", "deleted"], do: if(status == "added", do: "success", else: "error")
  def file_status(_status), do: "attention"

  @doc "Where a test sits: its target and suite."
  def test_location(%{module_name: module, suite_name: ""}), do: module
  def test_location(%{module_name: module, suite_name: suite}), do: "#{module} • #{suite}"
end
