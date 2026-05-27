defmodule TuistWeb.Utilities.Formatter do
  @moduledoc """
  Display-friendly wrappers around `Tuist.Utilities.DateFormatter`
  and friends. Each helper collapses the "value is missing" case
  (nil, empty string, non-positive duration) to a single en-dash
  `"–"` so tables and metadata grids stay clean without every
  caller threading its own `case ts do nil -> "–"; …`.

  Pure formatting only — no domain logic. Caller-side branching
  on `status` / lifecycle state belongs in the LiveView that owns
  the page.
  """

  alias Tuist.Utilities.DateFormatter

  @dash "–"

  @doc """
  Renders a duration in milliseconds as a human string. Accepts
  ints (lifecycle diffs) and floats (ClickHouse aggregates like
  `avgIf(toUnixTimestamp64Milli(?) - …)`). Exactly `0` renders as
  `"0s"` (zero is real data — e.g. cold-account analytics widget);
  `nil` / negative / non-numeric values collapse to the dash.
  """
  def format_duration_ms(0), do: "0s"

  def format_duration_ms(ms) when is_number(ms) and ms > 0, do: DateFormatter.format_duration_from_milliseconds(round(ms))

  def format_duration_ms(_), do: @dash

  @doc """
  Relative-time formatter for a DateTime — "5 minutes ago", "in
  1 hour", etc. `nil` collapses to the dash so the cell stays
  clean for rows whose timestamp hasn't been set yet (NULL
  lifecycle slot).
  """
  def format_relative_time(%DateTime{} = ts), do: DateFormatter.from_now(ts)
  def format_relative_time(_), do: @dash

  @doc """
  Absolute UTC formatter — "2026-05-27 14:23:11 UTC". Used in
  tooltips and detail pages where the relative form is too vague.
  """
  def format_absolute(%DateTime{} = ts), do: Calendar.strftime(ts, "%Y-%m-%d %H:%M:%S UTC")
  def format_absolute(_), do: @dash

  @doc """
  String display helper. Empty / nil → dash, binaries pass
  through unchanged, anything else gets `to_string/1`'d.
  """
  def display(""), do: @dash
  def display(nil), do: @dash
  def display(value) when is_binary(value), do: value
  def display(value), do: to_string(value)

  @doc """
  Wall-clock milliseconds elapsed since `ts`. Returns `0` for
  `nil` so callers computing "time since some lifecycle event"
  don't have to guard separately.
  """
  def ms_since(nil), do: 0
  def ms_since(%DateTime{} = ts), do: DateTime.diff(DateTime.utc_now(), ts, :millisecond)
end
