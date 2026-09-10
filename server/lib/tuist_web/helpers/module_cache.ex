defmodule TuistWeb.Helpers.ModuleCache do
  @moduledoc false
  use Gettext, backend: TuistWeb.Gettext

  def miss_reason_description(reason) do
    Enum.join([reason_description(reason), comparison_description()], " ")
  end

  def reason_description("changed") do
    dgettext(
      "dashboard_cache",
      "Changed: the module's own compared inputs changed, such as sources, resources, build settings, build configuration, or compiler version. This does not necessarily mean its source code was edited."
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
      "Cold: there is no earlier module observation to compare with, or the compared inputs did not explain the miss and we have no qualifying earlier remote hit for this exact key and endpoint. This includes repeated misses for keys that may never have been warmed; it does not prove the module was never cached."
    )
  end

  def reason_description("unavailable") do
    dgettext(
      "dashboard_cache",
      "Unavailable: this exact cache key was previously served remotely from the same recorded endpoint, but this run missed. Eviction, access, or transfer problems are possible; this label does not establish the cause."
    )
  end

  def reason_description("hit") do
    dgettext("dashboard_cache", "Cached: this observation reports a local or remote cache hit.")
  end

  def reason_description("all") do
    dgettext(
      "dashboard_cache",
      "Changed means the module's own compared inputs changed. Upstream means its dependency or external package hash changed. Unavailable means this exact key previously had a remote hit at the same endpoint but now misses. Cold covers missing comparison history or otherwise unexplained misses without that evidence."
    )
  end

  defp comparison_description do
    dgettext(
      "dashboard_cache",
      "Reasons compare the same module on the same branch within the selected date range and environment, using the inputs reported by the CLI. The previous observation may be a miss or a hit. Unavailable uses remote-hit reports received before this command started, across branches and CI/local runs in the same project and endpoint, within the 30-day history ending at the selected end date. Local hits and unknown endpoints do not establish remote availability. Not all cache-key inputs are available for comparison. Counts include reported observations. Older CLI versions may report an earlier build's cache results again from test shards."
    )
  end
end
