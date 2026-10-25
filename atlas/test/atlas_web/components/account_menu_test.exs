defmodule AtlasWeb.AccountMenuTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Atlas.Demo
  alias Atlas.Users.User
  alias AtlasWeb.AccountMenu
  alias AtlasWeb.NativeLinks.Config

  setup :verify_on_exit!

  setup do
    stub(Demo, :enabled?, fn -> false end)
    stub(Config, :origin, fn -> "https://atlas.example.org" end)
    :ok
  end

  test "offers Open in Atlas for the current page without its query string", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    {:ok, view, _html} = live(conn, "/tasks?q=secret-search")

    assert has_element?(
             view,
             ~s(#open-in-atlas[href="dev.tuist.atlas://navigate/tasks?server=https%3A%2F%2Fatlas.example.org"])
           )
  end

  test "follows LiveView navigation", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, "/tasks")

    {:ok, view, _html} = live_redirect(view, to: "/people")

    assert has_element?(view, ~s(#open-in-atlas[href^="dev.tuist.atlas://navigate/people?server="]))
  end

  test "refreshes on live patches within the same LiveView", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["admin:write"]})
    {:ok, view, _html} = live(conn, "/people/time-off")
    assert has_element?(view, ~s(#open-in-atlas[href^="dev.tuist.atlas://navigate/time-off?server="]))

    render_patch(view, "/people/time-off/settings")
    refute has_element?(view, "#open-in-atlas")

    render_patch(view, "/people/time-off?month=2026-05")
    assert has_element?(view, ~s(#open-in-atlas[href^="dev.tuist.atlas://navigate/time-off?server="]))
  end

  test "is available in account settings", %{conn: conn} do
    {conn, _user} = log_in_user(conn)

    {:ok, view, _html} = live(conn, "/settings")

    assert has_element?(view, ~s(#open-in-atlas[href^="dev.tuist.atlas://navigate/profile?server="]))
  end

  test "is hidden for pages without a native equivalent, without an HTTPS origin, and in demo mode" do
    user = %User{id: Uniq.UUID.uuid7(), name: "Test User", email: "test@tuist.dev"}

    for path <- ["/", "/settings/llm-providers", "/commercial/finance/vendors", nil] do
      refute render_component(&AccountMenu.headerbar/1, current_user: user, current_path: path) =~ "open-in-atlas"
    end

    assert render_component(&AccountMenu.headerbar/1, current_user: user, current_path: "/commercial/finance") =~
             "dev.tuist.atlas://navigate/invoices?server="

    stub(Config, :origin, fn -> nil end)
    refute render_component(&AccountMenu.headerbar/1, current_user: user, current_path: "/tasks") =~ "open-in-atlas"

    stub(Config, :origin, fn -> "https://atlas.example.org" end)
    stub(Demo, :enabled?, fn -> true end)
    refute render_component(&AccountMenu.headerbar/1, current_user: user, current_path: "/tasks") =~ "open-in-atlas"
  end
end
