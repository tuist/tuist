defmodule AtlasWeb.AccountSettingsLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "requires sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/settings")
  end

  test "general settings show the signed-in account and account navigation", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/settings")
    assert has_element?(view, "#account-layout")
    assert has_element?(view, "#account-general-link [data-selected]")
    assert has_element?(view, "#account-ai-providers-link[href='/settings/llm-providers']")
    assert has_element?(view, "#account-settings-name", user.name)
    assert has_element?(view, "#account-settings-email", user.email)
    assert has_element?(view, "#account-layout header [data-part='left-section'] a[href='/']")
    refute has_element?(view, "#account-settings-sidebar a[href='/']")
    refute has_element?(view, "#sidebar-commercial")
  end

  test "the dashboard account menu links to account settings", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/tasks")
    assert has_element?(view, "#personal-account-settings-link[href='/settings']", "Account settings")
    refute has_element?(view, "#account-settings-sidebar")
  end
end
