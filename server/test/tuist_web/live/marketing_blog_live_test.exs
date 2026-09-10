defmodule TuistWeb.Marketing.MarketingBlogLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Marketing.Blog.CoverArtwork
  alias Tuist.Marketing.Content

  describe "GET /blog" do
    test "renders the blog with the marketing stylesheet", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog")

      assert html =~ "/marketing/assets/bundle-new.css"
    end

    test "keeps the most recent post in the grid", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog")

      latest_post_title =
        "en" |> Content.get_entries() |> List.first() |> Content.get_entry_title()

      assert html |> posts_section() |> String.contains?(latest_post_title)
    end
  end

  describe "GET /blog (cover artwork)" do
    test "cards render the inline SVG cover for posts with artwork and the image otherwise", %{conn: conn} do
      stub(CoverArtwork, :available?, fn basename -> basename == "smart-before-fast" end)
      stub(CoverArtwork, :svg, fn "smart-before-fast", :page -> ~s(<svg data-part="artwork">cover</svg>) end)

      {:ok, _lv, html} = live(conn, ~p"/blog?category=learn")

      assert html =~ ~s(<svg data-part="artwork">cover</svg>)
      assert html =~ ~s(data-part="image")
    end

    test "case study cards render the customers page's cover artwork", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog?category=case-studies")

      # Monzo has a logo under priv/marketing/customers/logos, so its card
      # carries the generated dot-field artwork rather than the OG photo.
      assert html =~ ~s(<svg data-part="artwork")
      assert html =~ "Monzo"
    end
  end

  describe "GET /blog (view switcher)" do
    test "defaults to the card grid", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog")

      assert [_] = find(html, ~s(#marketing-blog > [data-part="posts"]))
      assert [] == find(html, ~s(#marketing-blog > [data-part="list"]))

      assert length(find(html, ~s(#marketing-blog > [data-part="posts"] > [data-part="post-item"] > [data-part="post"]))) ==
               9
    end

    test "?view=list renders rows of title, category and date cells", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog?view=list")

      assert [] == find(html, ~s(#marketing-blog > [data-part="posts"]))

      rows = find(html, ~s(#marketing-blog > [data-part="list"] > [data-part="row-item"] > [data-part="row"]))

      # The list fits more per page than the card grid's 9.
      assert length(rows) == 20

      first_row = List.first(rows)
      assert [_] = Floki.find(first_row, ~s([data-column="title"]))
      assert [_] = Floki.find(first_row, ~s([data-column="category"]))
      assert [_] = Floki.find(first_row, ~s([data-column="date"]))
    end

    test "a remembered view cookie decides the first render", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> put_req_cookie("tuist_blog_view", "list")
        |> live(~p"/blog")

      assert [_] = find(html, ~s(#marketing-blog > [data-part="list"]))
    end

    test "an explicit view in the URL beats the remembered one", %{conn: conn} do
      {:ok, lv, html} =
        conn
        |> put_req_cookie("tuist_blog_view", "list")
        |> live(~p"/blog?view=grid")

      assert [_] = find(html, ~s(#marketing-blog > [data-part="posts"]))

      # Toggling back to the grid drops the param, which must not hand the
      # decision back to the cookie.
      html = lv |> element(~s([aria-label="Grid view"])) |> render_click()

      assert [_] = find(html, ~s(#marketing-blog > [data-part="posts"]))
    end

    test "the view survives filtering and pagination links", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/blog?view=list")

      html =
        lv
        |> element(~s([data-part="category"]), "Learn")
        |> render_click()

      assert [_] = find(html, ~s(#marketing-blog > [data-part="list"]))
      assert_patched(lv, "/blog?category=learn&view=list")
    end
  end

  describe "GET /blog (compact filters)" do
    test "the category dropdown lists every category plus All", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog")

      items = find(html, ~s([data-part="item"]))
      labels = Enum.map(items, &Floki.attribute(&1, "data-label"))

      assert ["All"] in labels
      assert ["Product"] in labels
    end

    test "the search field stays closed until the toggle is clicked", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/blog")

      assert [] == find(html, ~s([data-part="filters-bar"][data-search-open]))

      html = lv |> element(~s([data-part="search-toggle"])) |> render_click()

      assert [_] = find(html, ~s([data-part="filters-bar"][data-search-open]))
      assert [_] = find(html, ~s([data-part="clear-search"]))
    end

    test "an active query opens the field on load", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog?search=cache")

      assert [_] = find(html, ~s([data-part="filters-bar"][data-search-open]))
    end

    test "emptying the query keeps the field open, the X closes and clears it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/blog?search=cache")

      html = lv |> form(~s(#marketing-blog form), %{"search" => ""}) |> render_change()
      assert [_] = find(html, ~s([data-part="filters-bar"][data-search-open]))

      html = lv |> element(~s([data-part="clear-search"])) |> render_click()
      assert [] == find(html, ~s([data-part="filters-bar"][data-search-open]))
      assert_patched(lv, "/blog")
    end
  end

  defp find(html, selector) do
    html |> Floki.parse_document!() |> Floki.find(selector)
  end

  defp posts_section(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s([data-part="posts"]))
    |> Floki.raw_html()
  end
end
