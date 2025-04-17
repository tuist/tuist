defmodule TuistWeb.Marketing.MarketingBlogLive do
  @moduledoc false
  use TuistWeb, :live_view

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Blog

  def mount(params, _session, socket) do
    posts = Blog.get_posts()
    categories = Blog.get_categories()
    highlighted_posts = posts |> Enum.filter(& &1.highlighted) |> Enum.take(5)
    category = Map.get(params, "category")
    posts = if is_nil(category), do: posts, else: Enum.filter(posts, &(&1.category == category))

    socket =
      socket
      |> assign(:posts, posts)
      |> assign(:highlighted_posts, highlighted_posts)
      |> assign(:categories, categories)
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    posts = Blog.get_posts()
    category = Map.get(params, "category")
    hero_post = List.first(posts)

    posts = if is_nil(category), do: posts, else: Enum.filter(posts, &(&1.category == category))

    {:noreply,
     socket
     |> assign(:hero_post, hero_post)
     |> assign(:posts, posts)
     |> assign(
       :head_image,
       Tuist.Environment.app_url(path: "/marketing/images/og/blog.jpg")
     )
     |> assign(:head_title, "The Tuist Blog")
     |> assign(:head_include_blog_rss_and_atom, true)
     |> assign(:head_include_changelog_rss_and_atom, false)
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign_structured_data(get_blog_structured_markup_data(posts))
     |> assign(:head_description, gettext("Read engaging stories and expert insights."))}
  end
end
