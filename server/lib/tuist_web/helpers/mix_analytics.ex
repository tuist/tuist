defmodule TuistWeb.Helpers.MixAnalytics do
  @moduledoc """
  What the Mix dashboards share: turning the environment filter into query
  options, and analytics series into chart points.
  """

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
end
