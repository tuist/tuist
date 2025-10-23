defmodule TuistWeb.Marketing.MarketingChangelogLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Changelog

  @page_size 10

  def mount(params, _session, socket) do
    entries = Changelog.get_entries()
    categories = Changelog.get_categories()
    category = Map.get(params, "category")
    page = parse_page(params)

    filtered_entries =
      if is_nil(category), do: entries, else: Enum.filter(entries, &(&1.category == category))

    paginated_entries = Enum.take(filtered_entries, page * @page_size)
    has_more? = length(filtered_entries) > length(paginated_entries)

    socket =
      socket
      |> assign(:entries, paginated_entries)
      |> assign(:all_entries, filtered_entries)
      |> assign(:categories, categories)
      |> assign(:page, page)
      |> assign(:has_more?, has_more?)
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    entries = Changelog.get_entries()
    category = Map.get(params, "category")
    page = parse_page(params)

    filtered_entries =
      if is_nil(category), do: entries, else: Enum.filter(entries, &(&1.category == category))

    paginated_entries = Enum.take(filtered_entries, page * @page_size)
    has_more? = length(filtered_entries) > length(paginated_entries)

    {:noreply,
     socket
     |> assign(:entries, paginated_entries)
     |> assign(:all_entries, filtered_entries)
     |> assign(:page, page)
     |> assign(:category, category)
     |> assign(:has_more?, has_more?)
     |> assign(
       :head_image,
       Tuist.Environment.app_url(path: "/marketing/images/og/changelog.jpg")
     )
     |> assign(:head_title, "Tuist Changelog")
     |> assign(:head_include_blog_rss_and_atom, false)
     |> assign(:head_include_changelog_rss_and_atom, true)
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign_structured_data(get_changelog_structured_data(filtered_entries))
     |> assign(
       :head_description,
       dgettext(
         "marketing",
         "Stay updated with the latest changes and improvements in Tuist. Read our changelog for detailed information about new features, bug fixes, and enhancements."
       )
     )}
  end

  def handle_event("load_more", _params, socket) do
    new_page = socket.assigns.page + 1
    category = socket.assigns.category

    params =
      if is_nil(category) do
        %{"page" => new_page}
      else
        %{"category" => category, "page" => new_page}
      end

    {:noreply, push_patch(socket, to: ~p"/changelog?#{params}")}
  end

  defp parse_page(params) do
    case Map.get(params, "page") do
      nil -> 1
      page when is_binary(page) -> String.to_integer(page)
      page when is_integer(page) -> page
    end
  end
end
