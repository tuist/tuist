defmodule TuistWeb.Helpers.ModuleCache do
  @moduledoc false
  use Gettext, backend: TuistWeb.Gettext

  def miss_reason_description(reason), do: reason_description(reason)

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

  def reason_description("unavailable") do
    dgettext(
      "dashboard_cache",
      "This exact key previously had a remote hit at the same cache endpoint, but now misses. The cause is not yet known."
    )
  end

  def reason_description("hit") do
    dgettext("dashboard_cache", "This observation reports a local or remote cache hit.")
  end

  def reason_description("all") do
    dgettext(
      "dashboard_cache",
      "Changed: module inputs changed. Upstream: dependencies changed. Cold: insufficient evidence. Unavailable: a previously served key now misses."
    )
  end
end
