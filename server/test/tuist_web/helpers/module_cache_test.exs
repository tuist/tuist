defmodule TuistWeb.Helpers.ModuleCacheTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistWeb.Helpers.ModuleCache

  test "relative windows stay fixed until the date selection changes" do
    stub(DateTime, :utc_now, fn -> ~U[2026-09-10 10:00:00Z] end)
    snapshot = ModuleCache.analytics_period_assigns(%{}, %{})
    assert snapshot.analytics_period == {~U[2026-08-11 10:00:00Z], ~U[2026-09-10 10:00:00Z]}

    stub(DateTime, :utc_now, fn -> ~U[2026-09-11 11:00:00Z] end)
    assert ModuleCache.analytics_period_assigns(%{"analytics-date-range" => "last-30-days"}, snapshot) == snapshot

    changed = ModuleCache.analytics_period_assigns(%{"analytics-date-range" => "last-7-days"}, snapshot)
    assert changed.analytics_period == {~U[2026-09-04 11:00:00Z], ~U[2026-09-11 11:00:00Z]}

    fresh = ModuleCache.analytics_period_assigns(%{}, %{})
    assert fresh.analytics_period == {~U[2026-08-12 11:00:00Z], ~U[2026-09-11 11:00:00Z]}
  end

  test "custom date changes are applied exactly while table parameters preserve the period" do
    params = %{
      "analytics-date-range" => "custom",
      "analytics-start-date" => "2026-08-01T12:34:56Z",
      "analytics-end-date" => "2026-08-07T12:34:56Z"
    }

    snapshot = ModuleCache.analytics_period_assigns(params, %{})
    assert snapshot.analytics_period == {~U[2026-08-01 12:34:56Z], ~U[2026-08-07 12:34:56Z]}
    assert ModuleCache.analytics_period_assigns(Map.put(params, "q", "Core"), snapshot) == snapshot

    changed =
      params
      |> Map.put("analytics-end-date", "2026-08-08T12:34:56Z")
      |> ModuleCache.analytics_period_assigns(snapshot)

    assert changed.analytics_period == {~U[2026-08-01 12:34:56Z], ~U[2026-08-08 12:34:56Z]}
  end
end
