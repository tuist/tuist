defmodule TuistWeb.Helpers.GradleTask do
  @moduledoc false
  use Gettext, backend: TuistWeb.Gettext

  def outcome_color("local_hit"), do: "information"
  def outcome_color("cache_hit"), do: "information"
  def outcome_color("remote_hit"), do: "information"
  def outcome_color("up_to_date"), do: "primary"
  def outcome_color("executed"), do: "success"
  def outcome_color("failed"), do: "destructive"
  def outcome_color(_), do: "neutral"

  def outcome_label("local_hit"), do: dgettext("dashboard_gradle", "Local hit")
  def outcome_label("cache_hit"), do: dgettext("dashboard_gradle", "Cache hit")
  def outcome_label("remote_hit"), do: dgettext("dashboard_gradle", "Remote hit")
  def outcome_label("up_to_date"), do: dgettext("dashboard_gradle", "Up-to-date")
  def outcome_label("executed"), do: dgettext("dashboard_gradle", "Succeeded")
  def outcome_label("failed"), do: dgettext("dashboard_gradle", "Failed")
  def outcome_label("skipped"), do: dgettext("dashboard_gradle", "Skipped")
  def outcome_label("no_source"), do: dgettext("dashboard_gradle", "No source")
  def outcome_label(other), do: other
end
