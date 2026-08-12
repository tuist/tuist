defmodule TuistWeb.Marketing.MarketingBlogPostLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.CSP, only: [get_csp_nonce: 0]
  import TuistWeb.Marketing.MarketingHTML, only: [marketing_banner: 1]
  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Blog
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Marketing.Design
  alias TuistWeb.Marketing.Localization

  on_mount {TuistWeb.Authentication, :mount_current_user}

  embed_templates "marketing_blog_post_live/*"
  # The redesigned template lives in new/; the suffix keeps its function name
  # (blog_post_new/1) distinct from the legacy blog_post/1.
  embed_templates "marketing_blog_post_live/new/*", suffix: "_new"

  def render(%{new_design: true} = assigns), do: blog_post_new(assigns)
  def render(assigns), do: blog_post(assigns)

  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:csp_nonce, get_csp_nonce())
     |> assign(:new_design, Design.new?(session, :blog_post))}
  end

  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    request_path = Localization.path_without_locale(uri.path)

    post = Enum.find(Blog.get_posts(), &(&1.slug == String.trim_trailing(request_path, "/")))

    if is_nil(post) do
      raise NotFoundError
    end

    author = Blog.get_authors()[post.author]
    post_image_url = post_image_url(post)

    # The redesigned page closes with the three most recent other posts;
    # get_posts/0 is already newest-first.
    read_next_posts =
      Blog.get_posts()
      |> Enum.reject(&(&1.slug == post.slug))
      |> Enum.take(3)

    current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")

    socket =
      socket
      |> assign(:current_path, current_path)
      |> assign(:post, post)
      |> assign(:author, author)
      |> assign(:read_next_posts, read_next_posts)
      |> assign(:head_title, post.title)
      |> assign(:head_description, post.excerpt)
      |> assign(:head_keywords, post.tags)
      |> assign(:head_fediverse_creator, author["fediverse_username"])
      |> assign(
        :head_image,
        post_image_url
      )
      |> assign(:post_image_url, post_image_url)
      |> assign(:head_twitter_card, "summary_large_image")
      |> assign_structured_data(get_blog_post_structured_markup_data(post))
      |> assign_structured_data(
        get_breadcrumbs_structured_data([
          {dgettext("marketing", "Tuist"), Tuist.Environment.app_url(path: ~p"/")},
          {dgettext("marketing", "Blog"), Tuist.Environment.app_url(path: ~p"/blog")},
          {post.title, Tuist.Environment.app_url(path: post.slug)}
        ])
      )

    {:noreply, socket}
  end

  defp post_image_url(post) do
    path =
      post.og_image_path ||
        OpenGraph.image_path(:marketing_text, title: post.title)

    Tuist.Environment.app_url(path: path, marketing: true)
  end

  def render_post_body(post, assigns) do
    if post.live do
      {rendered, _} =
        Code.eval_quoted(post.body_template, [assigns: assigns], Macro.Env.prune_compile_info(__ENV__))

      rendered
    else
      post.body
      |> TuistWeb.Marketing.MarketingHTML.content_html()
      |> raw()
    end
  end
end
