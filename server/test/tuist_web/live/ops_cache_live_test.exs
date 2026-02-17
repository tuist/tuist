defmodule TuistWeb.OpsCacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CacheEndpoints
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    Tuist.Repo.delete_all(CacheEndpoints.CacheEndpoint)

    user = AccountsFixtures.user_fixture(preload: [:account])

    conn = log_in_user(conn, user)

    Mimic.stub(Environment, :ops_user_handles, fn -> [user.account.name] end)

    %{conn: conn, user: user}
  end

  test "renders the cache endpoints page", %{conn: conn} do
    # Given
    {:ok, _endpoint} =
      CacheEndpoints.create_cache_endpoint(%{
        url: "https://cache-test.tuist.dev",
        display_name: "Test Node"
      })

    # When
    {:ok, _lv, html} = live(conn, ~p"/ops/cache")

    # Then
    assert html =~ "Cache Endpoints"
    assert html =~ "Test Node"
    assert html =~ "https://cache-test.tuist.dev"
    assert html =~ "Enabled"
  end

  test "toggles enabled state", %{conn: conn} do
    # Given
    {:ok, endpoint} =
      CacheEndpoints.create_cache_endpoint(%{
        url: "https://cache-test.tuist.dev",
        display_name: "Test Node"
      })

    {:ok, lv, _html} = live(conn, ~p"/ops/cache")

    # When
    lv |> element("button", "Disable") |> render_click()

    # Then
    {:ok, updated_endpoint} = CacheEndpoints.get_cache_endpoint(endpoint.id)
    assert updated_endpoint.enabled == false
  end

  test "deletes an endpoint", %{conn: conn} do
    # Given
    {:ok, endpoint} =
      CacheEndpoints.create_cache_endpoint(%{
        url: "https://cache-test.tuist.dev",
        display_name: "Test Node"
      })

    {:ok, lv, _html} = live(conn, ~p"/ops/cache")

    # When
    lv |> element("button", "Delete") |> render_click()

    # Then
    assert {:error, :not_found} = CacheEndpoints.get_cache_endpoint(endpoint.id)
  end

  test "adds a new endpoint", %{conn: conn} do
    # Given
    {:ok, lv, _html} = live(conn, ~p"/ops/cache")

    # When
    lv
    |> form("form", %{
      url: "https://cache-new.tuist.dev",
      display_name: "New Node"
    })
    |> render_submit()

    # Then
    endpoints = CacheEndpoints.list_cache_endpoints()
    assert Enum.any?(endpoints, fn e -> e.display_name == "New Node" end)
  end

  test "shows empty state when no endpoints exist", %{conn: conn} do
    # When
    {:ok, _lv, html} = live(conn, ~p"/ops/cache")

    # Then
    assert html =~ "No cache endpoints"
    assert html =~ "Add a cache endpoint to get started"
  end
end
