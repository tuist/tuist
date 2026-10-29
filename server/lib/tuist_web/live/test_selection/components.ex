defmodule TuistWeb.TestSelection.Components do
  @moduledoc """
  The cells and words the Test Selection pages share: a decision as a badge,
  the reasons behind it, a test's outcome, whether a selection run's skips
  were applied and why it fell back to running everything, and the kinds of
  changed files.
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

  @doc "A test's reason, short enough for a table cell."
  def reason_label("impacted"), do: dgettext("dashboard_tests", "Executes a changed file")
  def reason_label("target_changed"), do: dgettext("dashboard_tests", "Its target changed")
  def reason_label("failed_at_baseline"), do: dgettext("dashboard_tests", "Failed at the baseline")
  def reason_label("no_evidence"), do: dgettext("dashboard_tests", "No evidence")
  def reason_label("run_all"), do: dgettext("dashboard_tests", "Ran everything")
  def reason_label("unaffected"), do: dgettext("dashboard_tests", "No executed file changed")
  def reason_label(reason), do: reason

  @doc "A test's reason, as the sentence its page explains it with."
  def reason_description("impacted", path),
    do:
      dgettext(
        "dashboard_tests",
        "The baseline's evidence shows it executed %{path}, which changed since, so it has to run again.", path: path)

  def reason_description("target_changed", path),
    do:
      dgettext(
        "dashboard_tests",
        "%{path} changed its target's hash and coverage can't tell which tests depend on it (a resource, a dependency or the project's configuration), so every test of the target runs.",
        path: path
      )

  def reason_description("failed_at_baseline", _path),
    do: dgettext("dashboard_tests", "It failed or flaked in the baseline run, so a past pass can't vouch for it.")

  def reason_description("no_evidence", _path),
    do:
      dgettext(
        "dashboard_tests",
        "The baseline recorded no coverage evidence of its own for it (it is new, it overlapped another test, or its target doesn't link TestCoverageAttribution), so Tuist can't tell what it depends on."
      )

  def reason_description("run_all", _path),
    do: dgettext("dashboard_tests", "The selection fell back to running every requested test.")

  def reason_description("unaffected", _path),
    do:
      dgettext(
        "dashboard_tests",
        "It passed in the baseline and none of the files it executed changed since, so running it again is not expected to add signal."
      )

  def reason_description(reason, _path), do: reason

  @doc "How a selection run decided what to skip."
  def strategy_label("module_hash"), do: dgettext("dashboard_tests", "Module hash")
  def strategy_label(_strategy), do: dgettext("dashboard_tests", "Coverage")

  def strategy_color("module_hash"), do: "neutral"
  def strategy_color(_strategy), do: "primary"

  @doc "Whether a selection run's skips were applied."
  def mode_label("enabled"), do: dgettext("dashboard_tests", "Enforced")
  def mode_label(_mode), do: dgettext("dashboard_tests", "Dry run")

  def mode_color("enabled"), do: "success"
  def mode_color(_mode), do: "attention"

  @doc "Why a selection run selected every test it requested, when it did."
  def fallback_label("no_baseline"), do: dgettext("dashboard_tests", "No baseline")
  def fallback_label("baseline_too_far"), do: dgettext("dashboard_tests", "Baseline too far back")
  def fallback_label("deepen_budget_exhausted"), do: dgettext("dashboard_tests", "History too shallow")
  def fallback_label("timeout"), do: dgettext("dashboard_tests", "Timed out")
  def fallback_label("platform_mismatch"), do: dgettext("dashboard_tests", "Different platform")
  def fallback_label(reason), do: reason

  def fallback_description("no_baseline"),
    do:
      dgettext(
        "dashboard_tests",
        "No ancestor of this commit has a complete full run with per-test evidence for the requested scope."
      )

  def fallback_description("baseline_too_far"),
    do: dgettext("dashboard_tests", "The nearest baseline is further back than the project allows.")

  def fallback_description("deepen_budget_exhausted"),
    do: dgettext("dashboard_tests", "The CLI couldn't fetch enough history to diff against the baseline in time.")

  def fallback_description("timeout"),
    do: dgettext("dashboard_tests", "The server didn't answer in time, so the run went ahead with every test.")

  def fallback_description("platform_mismatch"),
    do:
      dgettext(
        "dashboard_tests",
        "The baseline's evidence was recorded on a different platform, where tests can execute different files."
      )

  def fallback_description(reason), do: reason

  attr :outcome, :string, default: nil
  attr :decision, :string, required: true
  attr :mode, :string, required: true
  attr :reported, :boolean, default: true

  @doc "What happened to a requested test in the run that reported its results."
  def outcome_cell(assigns) do
    ~H"""
    <.status_badge_cell
      :if={missed?(assigns)}
      status="error"
      label={dgettext("dashboard_tests", "Missed")}
    />
    <.status_badge_cell
      :if={!missed?(assigns) and @outcome == "failure"}
      status="error"
      label={dgettext("dashboard_tests", "Failed")}
    />
    <.status_badge_cell
      :if={@outcome == "success"}
      status="success"
      label={dgettext("dashboard_tests", "Passed")}
    />
    <.status_badge_cell
      :if={@outcome == "skipped"}
      status="disabled"
      label={dgettext("dashboard_tests", "Skipped")}
    />
    <.status_badge_cell
      :if={is_nil(@outcome) and @reported and @decision == "selected"}
      status="warning"
      label={dgettext("dashboard_tests", "Planned, not run")}
    />
    <.status_badge_cell
      :if={is_nil(@outcome) and (@decision == "skipped" or !@reported)}
      status="disabled"
      label={dgettext("dashboard_tests", "Not run")}
    />
    """
  end

  defp missed?(%{outcome: "failure", decision: "skipped"}), do: true
  defp missed?(_assigns), do: false

  @doc "The outcome a run's test shows: a skipped test's outcome only counts in dry run."
  def visible_outcome(%{decision: "skipped"}, "enabled"), do: nil
  def visible_outcome(%{outcome: outcome}, _mode), do: outcome

  def file_kind_label("source"), do: dgettext("dashboard_tests", "Source")
  def file_kind_label("test"), do: dgettext("dashboard_tests", "Test")
  def file_kind_label("resource"), do: dgettext("dashboard_tests", "Resource")
  def file_kind_label("tracked"), do: dgettext("dashboard_tests", "Tracked")
  def file_kind_label("ignored"), do: dgettext("dashboard_tests", "Ignored")
  def file_kind_label(kind), do: kind

  def file_kind_color("tracked"), do: "warning"
  def file_kind_color("resource"), do: "attention"
  def file_kind_color("ignored"), do: "neutral"
  def file_kind_color("test"), do: "secondary"
  def file_kind_color(_kind), do: "information"

  def file_status_label("added"), do: dgettext("dashboard_tests", "Added")
  def file_status_label("deleted"), do: dgettext("dashboard_tests", "Deleted")
  def file_status_label(_status), do: dgettext("dashboard_tests", "Modified")

  def file_status(status) when status in ["added", "deleted"], do: if(status == "added", do: "success", else: "error")
  def file_status(_status), do: "attention"

  @doc "Where a test sits: its target and suite."
  def test_location(%{module_name: module, suite_name: ""}), do: module
  def test_location(%{module_name: module, suite_name: suite}), do: "#{module} • #{suite}"
end
