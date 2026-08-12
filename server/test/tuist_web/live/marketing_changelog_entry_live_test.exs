defmodule TuistWeb.Marketing.MarketingChangelogEntryLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Marketing.Changelog

  setup do
    %{entry: List.first(Changelog.get_entries())}
  end

  describe "GET /changelog/:id" do
    test "renders the legacy design and stylesheet by default", %{conn: conn, entry: entry} do
      {:ok, _lv, html} = live(conn, ~p"/changelog/#{entry.id}")

      assert html =~ "/marketing/assets/bundle.css"
      refute html =~ "/marketing/assets/bundle-new.css"
    end

    test "renders the new design and stylesheet when the page flag is enabled", %{conn: conn, entry: entry} do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_changelog_entry -> true
        _ -> false
      end)

      {:ok, _lv, html} = live(conn, ~p"/changelog/#{entry.id}")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end

    test "?design=new previews the new design", %{conn: conn, entry: entry} do
      {:ok, _lv, html} = live(conn, ~p"/changelog/#{entry.id}?design=new")

      assert html =~ "/marketing/assets/bundle-new.css"
    end
  end

  describe "GET /changelog/:id (new design)" do
    setup do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_changelog_entry -> true
        _ -> false
      end)

      :ok
    end

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
end
