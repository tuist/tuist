defmodule TuistWeb.Marketing.MarketingBlogLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Marketing.Content
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "GET /blog" do
    test "renders the legacy design and stylesheet by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog")

      assert html =~ "/marketing/assets/bundle.css"
      refute html =~ "/marketing/assets/bundle-new.css"
    end

    test "renders the new design and stylesheet when the page flag is enabled", %{conn: conn} do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_blog -> true
        _ -> false
      end)

      {:ok, _lv, html} = live(conn, ~p"/blog")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end

    test "renders the new design for a user actor-gated onto the page flag", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      user_id = user.id

      stub(FunWithFlags, :enabled?, fn _flag -> false end)

      stub(FunWithFlags, :enabled?, fn
        :new_marketing_blog, [for: %{id: ^user_id}] -> true
        _flag, _opts -> false
      end)

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/blog")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end

    test "the new design keeps the most recent post in the grid", %{conn: conn} do
      {:ok, _lv, legacy_html} = live(conn, ~p"/blog")

      stub(FunWithFlags, :enabled?, fn
        :new_marketing_blog -> true
        _ -> false
      end)

      {:ok, _lv, new_html} = live(conn, ~p"/blog")

      latest_post_title =
        "en" |> Content.get_entries() |> List.first() |> Content.get_entry_title()

      assert new_html |> posts_section() |> String.contains?(latest_post_title)
      refute legacy_html |> posts_section() |> String.contains?(latest_post_title)
    end
  end

  describe "GET /blog (new design view switcher)" do
    setup do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_blog -> true
        _ -> false
      end)

      :ok
    end

    test "defaults to the card grid", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog")

      assert [_] = find(html, ~s(#marketing-blog > [data-part="posts"]))
      assert [] == find(html, ~s(#marketing-blog > [data-part="list"]))
      assert length(find(html, ~s(#marketing-blog > [data-part="posts"] > [data-part="post"]))) == 9
    end

    test "?view=list renders rows of title, category and date cells", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog?view=list")

      assert [] == find(html, ~s(#marketing-blog > [data-part="posts"]))

      rows = find(html, ~s(#marketing-blog > [data-part="list"] > [data-part="row"]))

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
    setup do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_blog -> true
        _ -> false
      end)

      :ok
    end

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
