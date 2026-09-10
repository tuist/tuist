defmodule TuistWeb.Marketing.MarketingBlogPostLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Marketing.Blog
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "GET /blog/:year/:month/:day/:slug" do
    test "renders a blog post without errors", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog/2025/11/17/smart-before-fast")

      assert html =~ "Build Smart Before You Build Fast"
    end

    test "renders the legacy design and stylesheet by default", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog/2025/11/17/smart-before-fast")

      assert html =~ "/marketing/assets/bundle.css"
      refute html =~ "/marketing/assets/bundle-new.css"
    end

    test "renders the new design and stylesheet when the page flag is enabled", %{conn: conn} do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_blog_post -> true
        _ -> false
      end)

      {:ok, _lv, html} = live(conn, ~p"/blog/2025/11/17/smart-before-fast")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
      assert html =~ "Build Smart Before You Build Fast"
    end

    test "renders the new design for a user actor-gated onto the page flag", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      user_id = user.id

      stub(FunWithFlags, :enabled?, fn _flag -> false end)

      stub(FunWithFlags, :enabled?, fn
        :new_marketing_blog_post, [for: %{id: ^user_id}] -> true
        _flag, _opts -> false
      end)

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/blog/2025/11/17/smart-before-fast")

      assert html =~ "/marketing/assets/bundle-new.css"
      refute html =~ "/marketing/assets/bundle.css"
    end

    test "the new design closes with the three most recent other posts", %{conn: conn} do
      stub(FunWithFlags, :enabled?, fn
        :new_marketing_blog_post -> true
        _ -> false
      end)

      {:ok, _lv, html} = live(conn, ~p"/blog/2025/11/17/smart-before-fast")

      expected_titles =
        Blog.get_posts()
        |> Enum.reject(&(&1.slug == "/blog/2025/11/17/smart-before-fast"))
        |> Enum.take(3)
        |> Enum.map(& &1.title)

      read_next =
        html
        |> String.split(~s(data-part="read-next"))
        |> List.last()

      for title <- expected_titles do
        assert read_next =~ title |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      end
    end
  end
end
