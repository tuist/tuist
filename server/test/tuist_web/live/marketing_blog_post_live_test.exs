defmodule TuistWeb.Marketing.MarketingBlogPostLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Blog.CoverArtwork
  alias TuistWeb.Marketing.StructuredMarkup

  describe "GET /blog/:year/:month/:day/:slug" do
    test "renders a blog post without errors", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog/2025/11/17/smart-before-fast")

      assert html =~ "Build Smart Before You Build Fast"
    end

    test "renders the post with the marketing stylesheet", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog/2025/11/17/smart-before-fast")

      assert html =~ "/marketing/assets/bundle-new.css"
      assert html =~ "Build Smart Before You Build Fast"
    end

    test "renders the post's cover artwork inline and on the social card", %{conn: conn} do
      stub(CoverArtwork, :available?, fn basename -> basename == "smart-before-fast" end)
      stub(CoverArtwork, :svg, fn "smart-before-fast", _theme -> ~s(<svg data-part="artwork">cover</svg>) end)

      {:ok, _lv, html} = live(conn, ~p"/blog/2025/11/17/smart-before-fast")

      assert html =~ ~s(<div data-part="image"><svg data-part="artwork">cover</svg></div>)
      assert html =~ ~s(property="og:image" content=") <> Tuist.Environment.app_url(path: "/open-graph-images/")
    end

    test "closes with the three most recent other posts", %{conn: conn} do
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

    test "the Bazel announcement renders its live dashboard", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog/2026/09/09/bazel")

      assert html =~ ~s(data-part="bazel-dashboard-lab")
      assert html =~ "Live from tuist/kura"
      assert html =~ "No Bazel invocations in the last 30 days yet."
      assert html =~ ~s(data-part="bazel-timeline-showcase")
    end

    test "the new Tuist post renders the anonymized rack model", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog/2026/09/12/the-new-tuist")

      # The navbar and footer carry their own data-part="brand", so the
      # anonymisation check is scoped to the rack scene itself.
      rack_scene =
        html
        |> Floki.parse_document!()
        |> Floki.find(~s([data-part="rack-scene"]))
        |> Floki.raw_html()

      assert rack_scene =~ ~s(data-logo-src="/marketing/images/brand/tuist-logo.svg")
      refute rack_scene =~ ~s(data-part="brand")
      refute html =~ "RACK MODEL"
      refute html =~ "Panels removed"
      refute html =~ "PILOT CONFIGURATION"
      refute html =~ "RACK ELEVATION"
    end

    test "the new Tuist post exposes complete search metadata", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/blog/2026/09/12/the-new-tuist")

      assert html =~ "The new Tuist, from build toolchains to bare metal"
      assert html =~ "Tuist is becoming vertically integrated build infrastructure"

      post = Enum.find(Blog.get_posts(), &(&1.slug == "/blog/2026/09/12/the-new-tuist"))
      structured_data = StructuredMarkup.get_blog_post_structured_markup_data(post)

      assert [image_url] = structured_data["image"]
      assert image_url =~ "/marketing/images/blog/2026/09/12/og.png"
      refute Map.has_key?(structured_data, "articleBody")
    end
  end
end
