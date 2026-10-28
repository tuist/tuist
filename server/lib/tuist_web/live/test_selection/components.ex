defmodule TuistWeb.TestSelection.Components do
  @moduledoc """
  The cells and words the Test Selection pages share: a decision as a badge,
  the reasons behind decisions, what a plan decided on (tests or test
  targets) and whether its skips were applied, and the kinds of changed
  files.
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

  @doc "A decision's reason, short enough for a table cell."
  def reason_label("covers_changed_file"), do: dgettext("dashboard_tests", "Executes a changed file")
  def reason_label("no_evidence"), do: dgettext("dashboard_tests", "No evidence of its own")
  def reason_label("new_test"), do: dgettext("dashboard_tests", "New test")
  def reason_label("recently_failed"), do: dgettext("dashboard_tests", "Failed recently")
  def reason_label("flaky"), do: dgettext("dashboard_tests", "Flaky")
  def reason_label("unskippable"), do: dgettext("dashboard_tests", "Always runs")
  def reason_label("tracked_file_changed"), do: dgettext("dashboard_tests", "Tracked file changed")
  def reason_label("unattributed_change"), do: dgettext("dashboard_tests", "Non-code change in its target")
  def reason_label("no_baseline"), do: dgettext("dashboard_tests", "No baseline")
  def reason_label("unaffected"), do: dgettext("dashboard_tests", "No executed file changed")
  def reason_label(reason), do: reason

  @doc "A decision's reason, as the sentence a decision's page explains it with."
  def reason_description("covers_changed_file", count) do
    dngettext(
      "dashboard_tests",
      "It executed a file that changed since the baseline, so it has to run again.",
      "It executed %{count} files that changed since the baseline, so it has to run again.",
      count
    )
  end

  def reason_description("no_evidence", _count),
    do:
      dgettext(
        "dashboard_tests",
        "The baseline recorded no coverage evidence of its own for it (it overlapped another test, or its target doesn't link TestCoverageAttribution), so Tuist can't tell what it depends on."
      )

  def reason_description("new_test", _count),
    do: dgettext("dashboard_tests", "The baseline never ran it, so there is no evidence to skip it with.")

  def reason_description("recently_failed", _count),
    do: dgettext("dashboard_tests", "It failed in a recent run, so it runs until it passes again.")

  def reason_description("flaky", _count),
    do: dgettext("dashboard_tests", "It is flaky, so a past pass doesn't prove it would pass now.")

  def reason_description("unskippable", _count), do: dgettext("dashboard_tests", "It is marked to always run.")

  def reason_description("tracked_file_changed", _count),
    do:
      dgettext(
        "dashboard_tests",
        "A tracked file changed since the baseline (a dependency manifest or project configuration), which can change any test's result, so every test runs."
      )

  def reason_description("unattributed_change", _count),
    do:
      dgettext(
        "dashboard_tests",
        "A file coverage can't see changed in its target (a resource, such as strings or assets), so every test of the target runs."
      )

  def reason_description("no_baseline", _count),
    do: dgettext("dashboard_tests", "No full run with coverage evidence precedes this commit, so every test runs.")

  def reason_description("unaffected", _count),
    do:
      dgettext(
        "dashboard_tests",
        "It passed in the baseline and none of the files it executed changed since, so running it again is not expected to add signal."
      )

  def reason_description(reason, _count), do: reason

  @doc "What a plan decided on."
  def scope_label("target"), do: dgettext("dashboard_tests", "Per test target")
  def scope_label(_scope), do: dgettext("dashboard_tests", "Per test")

  @doc "Whether a plan's skips were applied."
  def mode_label("enabled"), do: dgettext("dashboard_tests", "Enforced")
  def mode_label(_mode), do: dgettext("dashboard_tests", "Dry run")

  def mode_color("enabled"), do: "success"
  def mode_color(_mode), do: "attention"

  @doc "Why a plan selected every test, when it did."
  def fallback_label("tracked_file_changed"), do: dgettext("dashboard_tests", "Ran everything: tracked file changed")
  def fallback_label("no_baseline"), do: dgettext("dashboard_tests", "Ran everything: no baseline")
  def fallback_label(reason), do: reason

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

  @doc "A decision's subject: the test's name, or the target's."
  def decision_title(%{scope_kind: "target", module_name: module}), do: module
  def decision_title(%{name: name}), do: name

  @doc "Where a decision sits: its target and suite, for a test."
  def decision_location(%{scope_kind: "target"}), do: nil
  def decision_location(%{module_name: module, suite_name: ""}), do: module
  def decision_location(%{module_name: module, suite_name: suite}), do: "#{module} • #{suite}"
end
