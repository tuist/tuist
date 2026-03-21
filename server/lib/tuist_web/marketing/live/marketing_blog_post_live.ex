defmodule TuistWeb.Marketing.MarketingBlogPostLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.CSP, only: [get_csp_nonce: 0]
  import TuistWeb.Marketing.MarketingHTML, only: [marketing_banner: 1]
  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Blog
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Marketing.Localization

  on_mount {TuistWeb.Authentication, :mount_current_user}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :csp_nonce, get_csp_nonce())}
  end

  def handle_params(_params, url, socket) do
    uri = URI.parse(url)
    request_path = Localization.path_without_locale(uri.path)

    post = Enum.find(Blog.get_posts(), &(&1.slug == String.trim_trailing(request_path, "/")))

    if is_nil(post) do
      raise NotFoundError
    end

    author = Blog.get_authors()[post.author]

    socket =
      socket
      |> assign(:post, post)
      |> assign(:author, author)
      |> assign(:head_title, post.title)
      |> assign(:head_description, post.excerpt)
      |> assign(:head_keywords, post.tags)
      |> assign(:head_fediverse_creator, author["fediverse_username"])
      |> assign(
        :head_image,
        Blog.get_post_image_url(post)
      )
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

  def render_post_body(post, assigns) do
    if post.live do
      {rendered, _} =
        Code.eval_quoted(post.body_template, [assigns: assigns], Macro.Env.prune_compile_info(__ENV__))

      rendered
    else
      raw(post.body)
    end
  end
end
