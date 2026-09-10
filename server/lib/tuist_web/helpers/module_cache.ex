defmodule TuistWeb.Helpers.ModuleCache do
  @moduledoc false
  use Gettext, backend: TuistWeb.Gettext

  alias TuistWeb.Helpers.DatePicker

  # Relative presets are a snapshot for this page. Recomputing "now" on a
  # table patch changes the query window and defeats reuse of loaded analytics.
  def analytics_period_assigns(params, assigns) do
    preset = params["analytics-date-range"] || "last-30-days"

    selection =
      if preset == "custom" do
        {preset, params["analytics-start-date"], params["analytics-end-date"]}
      else
        preset
      end

    period =
      if assigns[:module_cache_date_selection] == selection do
        assigns.analytics_period
      else
        DatePicker.date_picker_params(params, "analytics").period
      end

    %{analytics_preset: preset, analytics_period: period, module_cache_date_selection: selection}
  end

  def normalize_miss_reason(reason) when reason in ~w(all changed upstream cold evicted), do: reason
  def normalize_miss_reason(_), do: "all"

  def reason_description("changed") do
    dgettext(
      "dashboard_cache",
      "The module's reported inputs changed, such as its files, build settings, configuration, or compiler version."
    )
  end

  def reason_description("upstream") do
    dgettext(
      "dashboard_cache",
      "The module's own reported inputs stayed the same, but a dependency or external package hash changed."
    )
  end

  def reason_description("cold") do
    dgettext(
      "dashboard_cache",
      "No earlier comparison is available, or the reported inputs and remote-hit history do not explain this miss."
    )
  end

  def reason_description("evicted") do
    dgettext(
      "dashboard_cache",
      "This exact key previously had a remote hit at the same cache endpoint, but now misses. The cached artifact was most likely evicted."
    )
  end

  def reason_description("hit") do
    dgettext("dashboard_cache", "This observation reports a local or remote cache hit.")
  end

  def reason_description("all") do
    dgettext(
      "dashboard_cache",
      "Changed: module inputs changed. Upstream: dependencies changed. Cold: insufficient evidence. Evicted: a previously served key now misses."
    )
  end

  def reason_description(_), do: reason_description("all")
end
