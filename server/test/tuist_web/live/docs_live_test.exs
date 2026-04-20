defmodule TuistWeb.DocsLiveTest do
  use TuistTestSupport.Cases.ConnCase
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Environment

  setup do
    stub(Req, :get, fn _url, _opts ->
      {:ok, %{status: 200, body: %{"data" => []}}}
    end)

    stub(Environment, :ops_user_handles, fn -> [] end)

    :ok
  end

  describe "docs overview" do
    test "renders the install card as a clickable link target", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/en/docs")

      assert has_element?(
               lv,
               ~s([data-part="hero-card"]#docs-install-card[phx-click][role="link"][tabindex="0"])
             )
    end

    test "shows a Log in button with return_to when the user is not authenticated", %{
      conn: conn
    } do
      {:ok, _lv, html} = live(conn, ~p"/en/docs")

      assert html =~ ~s(href="/docs/login?return_to=%2Fen%2Fdocs")
      refute html =~ ~s(id="docs-account-dropdown")
    end

    test "shows the account dropdown with Dashboard primary action when authenticated", %{
      conn: conn
    } do
      user = user_fixture(preload: [:account])
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/en/docs")

      assert html =~ ~s(id="docs-account-dropdown")
      assert html =~ "Dashboard"
      refute html =~ "Account settings"
      assert html =~ ~s(/users/log_out?return_to=%2Fen%2Fdocs)
    end

    test "renders the mobile account dropdown when authenticated", %{conn: conn} do
      user = user_fixture(preload: [:account])
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/en/docs")

      assert html =~ ~s(id="docs-mobile-account-dropdown")
    end

    test "renders the mobile Log in button when unauthenticated", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/en/docs")

      [_, mobile_actions | _] = String.split(html, ~s(data-part="mobile-actions"))
      assert mobile_actions =~ ~s(href="/docs/login?return_to=%2Fen%2Fdocs")
      refute mobile_actions =~ ~s(id="docs-mobile-account-dropdown")
    end
  end
end
