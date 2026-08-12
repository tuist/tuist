defmodule TuistWeb.Marketing.MarketingBlogLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Content
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Marketing.Design
  alias TuistWeb.Marketing.Localization

  on_mount({TuistWeb.Authentication, :mount_current_user})

  # Columns of the redesigned post grid on desktop, used to pad the last row
  # with blank cells so its hairlines stay closed.
  @grid_columns 3
  # A card takes far more room than a list row, so each view gets the page size
  # that fills a screen without a wall of scrolling.
  @posts_per_page %{"grid" => 9, "list" => 20}

  embed_templates "marketing_blog_live/*"

  def render(%{new_design: true} = assigns), do: blog_new(assigns)
  def render(assigns), do: blog(assigns)

  def mount(_params, session, socket) do
    all_entries = Content.get_entries(current_locale())
    structured_posts = Blog.get_posts()

    socket =
      socket
      |> assign(:new_design, Design.new?(session, :blog))
      |> assign(:categories, Content.get_entry_categories())
      |> assign(:search_query, "")
      |> assign(:selected_category, nil)
      |> assign(:current_page, 1)
      |> assign(:total_pages, 1)
      |> assign(:highlighted_post, List.first(all_entries))
      |> assign(:filtered_posts, [])
      |> assign(:row_fillers, 0)
      |> assign(:view_mode, "grid")
      # The remembered view (cookie → session, see TuistWeb.Marketing
      # .Preferences) applies to the first render only; from then on the URL
      # carries the view, so toggling back to the grid isn't overridden by it.
      |> assign(:remembered_view, session["blog_view"])
      |> assign(:search_open, false)
      |> assign(:structured_posts, structured_posts)
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)

    {:ok, socket}
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def handle_params(params, _url, socket) do
    all_entries = Content.get_entries(current_locale())
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

    # The redesigned page has no highlighted post above the grid, so the most
    # recent entry stays in the grid there.
    filtered_posts =
      if socket.assigns.new_design do
        filtered_posts
      else
        Enum.reject(filtered_posts, fn post ->
          Content.get_entry_slug(post) == Content.get_entry_slug(highlighted_post)
        end)
      end

    # Calculate pagination
    view_mode = view_mode(params, socket.assigns[:remembered_view])
    per_page = @posts_per_page[view_mode]
    total_posts = length(filtered_posts)
    total_pages = max(ceil(total_posts / per_page), 1)
    page = min(max(page, 1), total_pages)
    start_index = (page - 1) * per_page
    paginated_posts = Enum.slice(filtered_posts, start_index, per_page)

    socket =
      socket
      |> assign(:highlighted_post, highlighted_post)
      |> assign(:filtered_posts, paginated_posts)
      |> assign(:row_fillers, rem(@grid_columns - rem(length(paginated_posts), @grid_columns), @grid_columns))
      |> assign(:search_query, search_query)
      |> assign(:selected_category, category)
      |> assign(:current_page, page)
      |> assign(:total_pages, total_pages)
      |> assign(:view_mode, view_mode)
      |> assign(:remembered_view, nil)
      # Only ever opened here, never closed: deleting the last character of a
      # query patches through this function, and collapsing the field mid-typing
      # would be maddening. "close_search" is what closes it.
      |> assign(:search_open, socket.assigns[:search_open] || search_query != "")
      |> assign(
        :head_image,
        Tuist.Environment.app_url(
          path:
            OpenGraph.image_path(:marketing_blog,
              title: dgettext("marketing", "Blog")
            )
        )
      )
      |> assign(:head_title, "The Tuist Blog")
      |> assign(:head_include_blog_rss_and_atom, true)
      |> assign(:head_include_changelog_rss_and_atom, false)
      |> assign(:head_twitter_card, "summary_large_image")
      |> put_structured_data(get_blog_structured_markup_data(socket.assigns.structured_posts))
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
    # Reset pagination and category when searching, but stay in the same view.
    {:noreply, push_patch(socket, to: blog_href(nil, search_query, 1, socket.assigns.view_mode), replace: true)}
  end

  def handle_event("select_category", %{"category" => category}, socket) do
    # Reset pagination and search when selecting category
    {:noreply, push_patch(socket, to: blog_href(category, "", 1, socket.assigns.view_mode))}
  end

  def handle_event("page_change", %{"page" => page}, socket) do
    %{search_query: search_query, selected_category: category, view_mode: view_mode} = socket.assigns

    {:noreply, push_patch(socket, to: blog_href(category, search_query, page, view_mode))}
  end

  def handle_event("open_search", _params, socket) do
    {:noreply, assign(socket, :search_open, true)}
  end

  defp entry_image_url(entry) do
    Content.get_entry_image_url(entry, &post_image_url/1)
  end

  defp post_image_url(post) do
    path =
      post.og_image_path ||
        OpenGraph.image_path(:marketing_text, title: post.title)

    Tuist.Environment.app_url(path: path, marketing: true)
  end

  def handle_event("close_search", _params, socket) do
    %{selected_category: category, view_mode: view_mode} = socket.assigns

    {:noreply,
     socket
     |> assign(:search_open, false)
     |> push_patch(to: blog_href(category, "", 1, view_mode))}
  end

  defp category_label(nil), do: dgettext("marketing", "All")
  defp category_label(category), do: category |> to_string() |> String.capitalize()

  defp view_mode(params, remembered_view) do
    case Map.get(params, "view") do
      "list" -> "list"
      "grid" -> "grid"
      _ -> remembered_view || "grid"
    end
  end

  # Every filter, page and view link goes through here so switching one keeps
  # the others: the whole state of the index lives in the query string.
  defp blog_href(category, search, page, view) do
    query =
      [category: category, search: search, page: page, view: view]
      |> Enum.reject(fn {key, value} -> default_param?(key, value) end)
      |> Enum.map_join("&", fn {key, value} -> "#{key}=#{URI.encode_www_form(to_string(value))}" end)

    path = if query == "", do: "/blog", else: "/blog?#{query}"

    Localization.localized_href(path, current_locale())
  end

  defp default_param?(_key, value) when value in [nil, ""], do: true
  defp default_param?(:page, page), do: page in [1, "1"]
  defp default_param?(:view, view), do: view == "grid"
  defp default_param?(_key, _value), do: false

  defp current_locale do
    Gettext.get_locale(TuistWeb.Gettext)
  end
end
