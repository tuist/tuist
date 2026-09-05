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
    test "renders intent-specific starting paths", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/en/docs")

      assert has_element?(
               lv,
               ~s(a#docs-optimization-path[href="/en/docs/guides/get-started/optimization"]),
               "Optimize"
             )

      assert has_element?(
               lv,
               ~s(a#docs-observability-path[href="/en/docs/guides/get-started/observability"]),
               "Observe"
             )

      assert has_element?(
               lv,
               ~s(a#docs-runners-path[href="/en/docs/guides/get-started/tuist-runners"]),
               "Run"
             )

      assert has_element?(
               lv,
               ~s(a#docs-ask-path[href="/en/docs/guides/get-started/ask"]),
               "Ask"
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
      assert has_element?(lv, "#what-do-you-want-to-do", "What do you want to do?")
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

  describe "docs pages" do
    test "puts the page-owned template variables in a signed image URL", %{conn: conn} do
      {:ok, _live_view, html} = live(conn, ~p"/en/docs/guides/install-tuist")
      {:ok, document} = Floki.parse_document(html)
      [image] = Floki.attribute(document, "meta[property='og:image']", "content")
      uri = URI.parse(image)
      params = URI.decode_query(uri.query)

      assert uri.path =~ ~r|\A/open-graph-images/[0-9a-f]{64}\.jpg\z|
      assert params["template"] == "docs"
      assert params["title"] == "Install Tuist"
      assert params["category"] == "Guides"
      assert is_binary(params["signature"])
    end

    test "marks the page up as a TechArticle alongside its breadcrumbs", %{conn: conn} do
      {:ok, _live_view, html} = live(conn, ~p"/en/docs/guides/install-tuist")

      assert ["TechArticle", "BreadcrumbList"] = structured_data_types(html)
    end

    test "marks the docs landing page up as a TechArticle too", %{conn: conn} do
      {:ok, _live_view, html} = live(conn, ~p"/en/docs")

      assert "TechArticle" in structured_data_types(html)
    end

    test "links the page to its own markdown twin", %{conn: conn} do
      {:ok, _live_view, html} = live(conn, ~p"/en/docs/guides/install-tuist")
      {:ok, document} = Floki.parse_document(html)

      assert [markdown_url] = Floki.attribute(document, "link[type='text/markdown']", "href")
      assert markdown_url == Tuist.Environment.app_url(path: "/en/docs-markdown/guides/install-tuist")
    end

    @tag :locale
    test "keeps a fallback locale's metadata on the requested locale, not English", %{conn: conn} do
      # `Docs.get_page/1` serves the English page when a locale has no
      # translation. The markup must still describe the URL that was requested,
      # or the page contradicts its own canonical link.
      {:ok, _live_view, html} = live(conn, "/es/docs/guides/install-tuist")
      {:ok, document} = Floki.parse_document(html)

      assert [canonical] = Floki.attribute(document, "link[rel='canonical']", "href")
      assert canonical == Tuist.Environment.app_url(path: "/es/docs/guides/install-tuist")

      assert [markdown_url] = Floki.attribute(document, "link[type='text/markdown']", "href")
      assert markdown_url == Tuist.Environment.app_url(path: "/es/docs-markdown/guides/install-tuist")

      tech_article = html |> structured_data() |> Enum.find(&(&1["@type"] == "TechArticle"))
      assert tech_article["url"] == Tuist.Environment.app_url(path: "/es/docs/guides/install-tuist")

      breadcrumbs = html |> structured_data() |> Enum.find(&(&1["@type"] == "BreadcrumbList"))
      refute Enum.any?(breadcrumbs["itemListElement"], &String.contains?(&1["item"], "/en/"))
    end
  end

  defp structured_data(html) do
    {:ok, document} = Floki.parse_document(html)

    document
    |> Floki.find("script[type='application/ld+json']")
    # Floki.text/1 drops the contents of script tags unless told otherwise.
    |> Enum.map(&(&1 |> Floki.text(js: true) |> String.trim() |> JSON.decode!()))
  end

  defp structured_data_types(html), do: html |> structured_data() |> Enum.map(& &1["@type"])
end
