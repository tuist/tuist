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

      assert html =~ "/marketing/assets/bundle-new.css"
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
