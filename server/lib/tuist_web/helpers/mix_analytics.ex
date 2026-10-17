defmodule TuistWeb.Helpers.MixAnalytics do
  @moduledoc """
  What the Mix dashboards share: turning the environment filter into query
  options and labels, and analytics series into chart points.
  """
  use Gettext, backend: TuistWeb.Gettext

  @doc """
  The query options for an environment filter value. Anything other than
  `"ci"` or `"local"`, `"any"` included, filters nothing.
  """
  def environment_opts("ci"), do: [is_ci: true]
  def environment_opts("local"), do: [is_ci: false]
  def environment_opts(_any), do: []

  @doc """
  Chart points, `[date, seconds]`, for a series of durations in milliseconds.
  A bucket without data is drawn at zero.
  """
  def duration_points(%{dates: dates, values: values}) do
    Enum.zip_with(dates, values, &[&1, seconds(&2)])
  end

  @doc """
  Milliseconds as seconds with one decimal, the unit the charts are labelled in.
  """
  def seconds(nil), do: 0
  def seconds(milliseconds), do: (milliseconds / 1000) |> Decimal.from_float() |> Decimal.round(1)

  def environment_label("local"), do: dgettext("dashboard_gradle", "Local")
  def environment_label("ci"), do: dgettext("dashboard_gradle", "CI")
  def environment_label(_any), do: dgettext("dashboard_gradle", "Any")

  def analytics_trend_label("last-24-hours"), do: dgettext("dashboard_gradle", "since yesterday")
  def analytics_trend_label("last-7-days"), do: dgettext("dashboard_gradle", "since last week")
  def analytics_trend_label("last-12-months"), do: dgettext("dashboard_gradle", "since last year")
  def analytics_trend_label("custom"), do: dgettext("dashboard_gradle", "since last period")
  def analytics_trend_label(_), do: dgettext("dashboard_gradle", "since last month")
end
