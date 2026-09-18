defmodule AtlasWeb.OverviewLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Mimic
  import Phoenix.LiveViewTest

  alias Atlas.TuistOverview

  setup :set_mimic_from_context
  setup :verify_on_exit!

  setup do
    stub(TuistOverview, :recent_organizations, fn -> {:ok, []} end)
    stub(TuistOverview, :recent_organizations, fn _opts -> {:ok, []} end)
    :ok
  end

  defp measurements do
    %{
      users:
        {:ok,
         %{
           total: 1234,
           current_value: 1234,
           previous_value: 1000,
           delta_pct: 23.4,
           series: [{~D[2026-09-01], 1000}, {~D[2026-09-30], 1234}]
         }},
      organizations:
        {:ok,
         %{
           total: 56,
           current_value: 56,
           previous_value: 50,
           delta_pct: 12.0,
           series: [{~D[2026-09-01], 50}, {~D[2026-09-30], 56}]
         }},
      projects:
        {:ok,
         %{
           total: 789,
           current_value: 789,
           previous_value: 700,
           delta_pct: 12.7,
           series: [{~D[2026-09-01], 700}, {~D[2026-09-30], 789}]
         }},
      jobs:
        {:ok,
         %{
           total: 4321,
           current_value: 4321,
           previous_value: 4000,
           delta_pct: 8.0,
           series: [{~D[2026-09-01], 100}, {~D[2026-09-30], 200}]
         }},
      cache_operations:
        {:ok,
         %{
           total: 12_345_678,
           current_value: 12_345_678,
           previous_value: 10_000_000,
           delta_pct: 23.5,
           series: [{~D[2026-09-01], 400_000}, {~D[2026-09-30], 500_000}]
         }}
    }
  end

  test "renders every Tuist stat and the default widget's chart", %{conn: conn} do
    stub(TuistOverview, :measure, fn _range, _opts -> measurements() end)
    stub(TuistOverview, :measure, fn _range -> measurements() end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#overview")
    assert has_element?(view, "#overview-widget-users [data-part='value']", "1,234")
    assert has_element?(view, "#overview-widget-organizations [data-part='value']", "56")
    assert has_element?(view, "#overview-widget-projects [data-part='value']", "789")
    assert has_element?(view, "#overview-widget-jobs [data-part='value']", "4,321")
    assert has_element?(view, "#overview-widget-cache-operations [data-part='value']", "12,345,678")
    # Users is the default selected widget.
    assert has_element?(view, "[id^='overview-chart-users-']")
    assert has_element?(view, "#overview-date-range-picker")
  end

  test "clicking a widget swaps in that metric's chart", %{conn: conn} do
    stub(TuistOverview, :measure, fn _range -> measurements() end)
    stub(TuistOverview, :measure, fn _range, _opts -> measurements() end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "select_widget", %{"widget" => "cache_operations"})

    assert has_element?(view, "[id^='overview-chart-cache_operations-']")
    refute has_element?(view, "[id^='overview-chart-users-']")
  end

  test "shows an empty state when the Tuist server is not connected", %{conn: conn} do
    stub(TuistOverview, :measure, fn _range -> Map.new(TuistOverview.metrics(), &{&1, {:error, :not_configured}}) end)

    stub(TuistOverview, :measure, fn _range, _opts ->
      Map.new(TuistOverview.metrics(), &{&1, {:error, :not_configured}})
    end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#overview-widget-users [data-part='empty-label']", "Not connected")
  end

  test "reports an unavailable state for a single failed metric without hiding the rest", %{conn: conn} do
    stub(TuistOverview, :measure, fn _range ->
      measurements()
      |> Map.put(:users, {:error, :timeout})
    end)

    stub(TuistOverview, :measure, fn _range, _opts ->
      measurements()
      |> Map.put(:users, {:error, :timeout})
    end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#overview-widget-users [data-part='empty-label']", "Unavailable")
    assert has_element?(view, "#overview-widget-organizations [data-part='value']", "56")
  end

  test "redirects unauthenticated visitors to /login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end
end
