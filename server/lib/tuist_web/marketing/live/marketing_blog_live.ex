defmodule TuistWeb.Marketing.MarketingBlogLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Content

  on_mount {TuistWeb.Authentication, :mount_current_user}

  @posts_per_page 9

  def mount(_params, _session, socket) do
    all_entries = Content.get_entries()
    structured_posts = Blog.get_posts()

    socket =
      socket
      |> assign(:categories, Content.get_entry_categories())
      |> assign(:search_query, "")
      |> assign(:selected_category, nil)
      |> assign(:current_page, 1)
      |> assign(:total_pages, 1)
      |> assign(:highlighted_post, List.first(all_entries))
      |> assign(:filtered_posts, [])
      |> assign(:structured_posts, structured_posts)
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    all_entries = Content.get_entries()
    search_query = Map.get(params, "search", "")
    category = Map.get(params, "category")

    page =
      case Integer.parse(Map.get(params, "page", "1")) do
        {num, ""} when num > 0 -> num
        _ -> 1
      end

    # Check if page changed (for scroll behavior)
    previous_page = Map.get(socket.assigns, :current_page, 1)
    page_changed = page != previous_page

    highlighted_post = List.first(all_entries)

    # Filter by search query (search across title, excerpt, and content)
    filtered_posts =
      if search_query == "" do
        all_entries
      else
        query_lower = String.downcase(search_query)

        Enum.filter(all_entries, fn entry ->
          entry_title = entry |> Content.get_entry_title() |> String.downcase()
          entry_excerpt = entry |> Content.get_entry_excerpt() |> String.downcase()
          entry_body = entry |> Content.get_entry_body() |> String.downcase()

          String.contains?(entry_title, query_lower) ||
            String.contains?(entry_excerpt, query_lower) ||
            String.contains?(entry_body, query_lower)
        end)
      end

    # Filter by category
    filtered_posts =
      if is_nil(category) or category == "" do
        filtered_posts
      else
        Enum.filter(filtered_posts, &(Content.get_entry_category(&1) == category))
      end

    filtered_posts =
      Enum.reject(filtered_posts, fn post ->
        Content.get_entry_slug(post) == Content.get_entry_slug(highlighted_post)
      end)

    # Calculate pagination
    total_posts = length(filtered_posts)
    total_pages = max(ceil(total_posts / @posts_per_page), 1)
    page = min(max(page, 1), total_pages)
    start_index = (page - 1) * @posts_per_page
    paginated_posts = Enum.slice(filtered_posts, start_index, @posts_per_page)

    socket =
      socket
      |> assign(:highlighted_post, highlighted_post)
      |> assign(:filtered_posts, paginated_posts)
      |> assign(:search_query, search_query)
      |> assign(:selected_category, category)
      |> assign(:current_page, page)
      |> assign(:total_pages, total_pages)
      |> assign(
        :head_image,
        Tuist.Environment.app_url(path: "/marketing/images/og/blog.jpg")
      )
      |> assign(:head_title, "The Tuist Blog")
      |> assign(:head_include_blog_rss_and_atom, true)
      |> assign(:head_include_changelog_rss_and_atom, false)
      |> assign(:head_twitter_card, "summary_large_image")
      |> assign_structured_data(get_blog_structured_markup_data(socket.assigns.structured_posts))
      |> assign(
        :head_description,
        dgettext("marketing", "Read engaging stories and expert insights.")
      )

    # Push scroll event only if page changed
    socket =
      if page_changed and socket.assigns[:live_action] != :mount do
        push_event(socket, "scroll-to-target", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => search_query}, socket) do
    # Reset pagination and category when searching
    {:noreply, push_patch(socket, to: ~p"/blog?search=#{search_query}")}
  end

  def handle_event("select_category", %{"category" => category}, socket) do
    # Reset pagination and search when selecting category
    {:noreply, push_patch(socket, to: ~p"/blog?category=#{category}")}
  end

  def handle_event("page_change", %{"page" => page}, socket) do
    params = []

    params =
      if socket.assigns.search_query == "",
        do: params,
        else: ["search=#{URI.encode_www_form(socket.assigns.search_query)}" | params]

    params =
      if socket.assigns.selected_category,
        do: ["category=#{socket.assigns.selected_category}" | params],
        else: params

    params = ["page=#{page}" | params]
    query_string = "?#{Enum.join(params, "&")}"

    {:noreply, push_patch(socket, to: "/blog#{query_string}")}
  end
end
