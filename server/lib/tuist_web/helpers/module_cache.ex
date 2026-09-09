defmodule TuistWeb.Helpers.ModuleCache do
  @moduledoc false
  use Gettext, backend: TuistWeb.Gettext

  def miss_reason_description(reason) do
    Enum.join([reason_description(reason), comparison_description()], " ")
  end

  def reason_description("changed") do
    dgettext(
      "dashboard_cache",
      "Changed: the module's own compared inputs changed, such as sources, resources, or build settings. This does not necessarily mean its source code was edited."
    )
  end

  def reason_description("upstream") do
    dgettext(
      "dashboard_cache",
      "Upstream: the module's own compared inputs stayed the same, but its dependency or external package hash changed."
    )
  end

  def reason_description("cold") do
    dgettext(
      "dashboard_cache",
      "Cold: there is no earlier observation to compare with, or the compared inputs did not explain the miss. This can include repeated misses for the same cache key; it does not mean the module was never cached."
    )
  end

  def reason_description("hit") do
    dgettext("dashboard_cache", "Cached: this observation reports a local or remote cache hit.")
  end

  def reason_description("all") do
    dgettext(
      "dashboard_cache",
      "Changed means the module's own compared inputs changed. Upstream means its dependency or external package hash changed. Cold means there is no earlier observation, or the compared inputs did not explain the miss."
    )
  end

  defp comparison_description do
    dgettext(
      "dashboard_cache",
      "Reasons compare the same module on the same branch within the selected date range and environment, using the inputs reported by the CLI. The previous observation may be a miss or a hit. Not all cache-key inputs are available for comparison. Counts include reported observations; test shards can repeat an earlier build's cache results."
    )
  end
end
