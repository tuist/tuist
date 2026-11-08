defmodule TuistWeb.Marketing.MarketingChangelogEntryLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Marketing.Changelog

  setup do
    %{entry: List.first(Changelog.get_entries())}
  end

  describe "GET /changelog/:id" do
    test "renders the page with the marketing stylesheet", %{conn: conn, entry: entry} do
      {:ok, _lv, html} = live(conn, ~p"/changelog/#{entry.id}")

      assert html =~ "/marketing/assets/bundle.css"
    end
  end

  describe "GET /changelog/:id (article)" do
    test "renders the entry with breadcrumb, title and date", %{conn: conn, entry: entry} do
      {:ok, _lv, html} = live(conn, ~p"/changelog/#{entry.id}")

      article = find(html, ~s(#marketing-changelog-entry > [data-part="article"]))

      assert [_] = article
      assert html =~ entry.title
      assert [_] = find(html, ~s([data-part="breadcrumb"]))
      assert [_] = find(html, ~s([data-part="header"] [data-part="date"]))
    end

    test "renders only the article, without read-next or CTA sections", %{conn: conn, entry: entry} do
      {:ok, _lv, html} = live(conn, ~p"/changelog/#{entry.id}")

      assert [] == find(html, ~s([data-part="read-next"]))
      assert [] == find(html, ~s(#marketing-changelog-entry [data-part="cta"]))
      assert [] == find(html, ~s(#marketing-changelog-entry [data-part="features-divider"]))
    end

    @tag :locale
    test "unavailable article locales temporarily redirect to English with the query intact", %{conn: conn} do
      for {locales, id} <- [
            {~w(yue_Hant ka ko ja), "2026.03.10-gradle-requested-tasks"},
            {~w(ko ja ru), "2026.07.02-test-run-errors"},
            {["ko"], "2026.03.19-failed-tests-pr-comment"},
            {["ko"], "2026.05.12-selective-testing-hit-filter"}
          ],
          locale <- locales do
        response = get(conn, "/#{locale}/changelog/#{id}?utm_source=audit&x=a%2Fb")
        assert redirected_to(response, 302) == "/changelog/#{id}?utm_source=audit&x=a%2Fb"
      end
    end

    test "English articles keep their self-canonical and only available language alternates", %{conn: conn} do
      path = "/changelog/2026.03.10-gradle-requested-tasks"
      html = conn |> get(path <> "?utm_source=audit") |> html_response(200)

      assert [Tuist.Environment.app_url(path: path)] ==
               html |> find(~s(link[rel="canonical"])) |> Floki.attribute("href")

      assert ["en", "x-default"] ==
               html |> find("link[hreflang]") |> Floki.attribute("hreflang")

      assert html |> find("#changelog-entry-content") |> Floki.text() =~ "explicitly requested"
    end

    @tag :locale
    test "unknown articles return 404 instead of redirecting to a missing English page", %{conn: conn} do
      for path <- ["/changelog/unknown-entry", "/ko/changelog/unknown-entry"] do
        assert_error_sent 404, fn -> get(conn, path) end
      end
    end
  end

  defp find(html, selector) do
    html |> Floki.parse_document!() |> Floki.find(selector)
  end

  describe "social metadata" do
    test "uses the first entry image in social metadata", %{conn: conn} do
      html =
        conn
        |> get("/changelog/2026.08.21-automation-configuration-history")
        |> html_response(200)

      document = Floki.parse_document!(html)

      assert Floki.attribute(Floki.find(document, ~s(meta[property="og:image"])), "content") == [
               Tuist.Environment.app_url(
                 path:
                   TuistWeb.Endpoint.static_path(
                     "/marketing/images/changelog/2026.08.21-automation-configuration-history.png"
                   )
               )
             ]

      assert Floki.find(document, ~s(meta[property="og:image:width"])) == []
      assert Floki.find(document, ~s(meta[property="og:image:height"])) == []
    end
  end
end
