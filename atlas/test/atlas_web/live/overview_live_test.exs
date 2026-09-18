defmodule AtlasWeb.OverviewLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Mimic
  import Phoenix.LiveViewTest

  alias Atlas.TuistOverview

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "renders every Tuist stat pulled from the read-only proxies", %{conn: conn} do
    stub(TuistOverview, :stats, fn ->
      %{
        users: {:ok, 1234},
        organizations: {:ok, 56},
        projects: {:ok, 789},
        jobs: {:ok, 4321},
        cache_operations: {:ok, 12_345_678}
      }
    end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#overview")
    assert has_element?(view, "#overview > [data-part='header'] [data-part='title']", "Overview")
    assert has_element?(view, "#overview-widget-users [data-part='value']", "1,234")
    assert has_element?(view, "#overview-widget-organizations [data-part='value']", "56")
    assert has_element?(view, "#overview-widget-projects [data-part='value']", "789")
    assert has_element?(view, "#overview-widget-jobs [data-part='value']", "4,321")
    assert has_element?(view, "#overview-widget-cache-operations [data-part='value']", "12,345,678")
  end

  test "shows an empty state when the Tuist server is not connected", %{conn: conn} do
    stub(TuistOverview, :stats, fn ->
      Map.new(
        [:users, :organizations, :projects, :jobs, :cache_operations],
        &{&1, {:error, :not_configured}}
      )
    end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#overview-widget-users [data-part='empty-label']", "Not connected")
    assert has_element?(view, "#overview-widget-cache-operations [data-part='empty-label']", "Not connected")
  end

  test "reports an unavailable state for a single failed stat without hiding the rest", %{conn: conn} do
    stub(TuistOverview, :stats, fn ->
      %{
        users: {:error, :timeout},
        organizations: {:ok, 10},
        projects: {:ok, 20},
        jobs: {:ok, 30},
        cache_operations: {:ok, 40}
      }
    end)

    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#overview-widget-users [data-part='empty-label']", "Unavailable")
    assert has_element?(view, "#overview-widget-organizations [data-part='value']", "10")
  end

  test "redirects unauthenticated visitors to /login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end
end
