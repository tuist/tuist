defmodule TuistWeb.Marketing.MarketingOverdriveComponents do
  @moduledoc """
  Shared pieces of the Overdrive directory and project pages.
  """
  use TuistWeb, :html

  alias Tuist.Marketing.Overdrive

  attr :stats, :map, required: true

  def overdrive_stats(assigns) do
    assigns = assign(assigns, :items, stat_items(assigns.stats))

    ~H"""
    <dl :if={@items != []} data-part="stats">
      <div :for={{label, value} <- @items} data-part="stat">
        <dt data-part="label">{label}</dt>
        <dd data-part="value">{value}</dd>
      </div>
    </dl>
    <p :if={@items == []} data-part="stats-empty">
      {dgettext(
        "marketing",
        "Numbers show up here as soon as the project runs builds and tests through Tuist."
      )}
    </p>
    """
  end

  def project_href(%{handle: handle}), do: TuistWeb.Marketing.MarketingHTML.localized_href("/overdrive/#{handle}")

  def dashboard_href(%{handle: handle}), do: "/#{handle}"

  defp stat_items(stats) do
    Enum.reject(
      [
        {dgettext("marketing", "Builds"), Overdrive.format_count(stats.builds)},
        {dgettext("marketing", "Cache hit rate"), Overdrive.format_percentage(stats.cache_hit_rate)},
        {dgettext("marketing", "Test runs"), Overdrive.format_count(stats.test_runs)},
        {dgettext("marketing", "Median build"), Overdrive.format_duration(stats.median_build_duration_ms)}
      ],
      fn {_label, value} -> is_nil(value) end
    )
  end
end
