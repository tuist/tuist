defmodule TuistWeb.DocsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts

  setup do
    stub(Req, :get, fn _url, _opts ->
      {:ok, %{status: 200, body: %{"data" => []}}}
    end)

    stub(Accounts, :tuist_operator?, fn _ -> false end)

    :ok
  end

  describe "docs overview" do
    test "renders setup-specific starting paths", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/en/docs")

      assert has_element?(
               lv,
               ~s(a#docs-generated-xcode-path[href="/en/docs/tutorials/xcode/create-a-generated-project"]),
               "Generated Xcode project"
             )

      assert has_element?(
               lv,
               ~s(a#docs-xcode-path[href="/en/docs/guides/features/cache/xcode-cache"]),
               "Xcode project"
             )

      assert has_element?(
               lv,
               ~s(a#docs-gradle-path[href="/en/docs/guides/install-gradle-plugin"]),
               "Gradle project"
             )

      assert has_element?(
               lv,
               ~s(a#docs-runners-path[href="/en/docs/guides/features/runners/getting-started"]),
               "CI runners"
             )
    end

    test "routes the generic cache card to the cache overview", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/en/docs")

      assert has_element?(
               lv,
               ~s(a#docs-cache-card[href="/en/docs/guides/features/cache"]),
               "Cache"
             )
    end

    test "positions Tuist as build infrastructure for Xcode and Gradle", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/en/docs")

      assert has_element?(lv, "h1", "One platform for faster build toolchains")
      assert has_element?(lv, "#start-with-your-setup", "Start with your setup")
      assert has_element?(lv, "#learn-more", "Explore Tuist's capabilities")
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
