defmodule TuistWeb.Marketing.MarketingChangelogLive do
  @moduledoc false
  use TuistWeb, :live_view

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.Changelog

  def mount(params, _session, socket) do
    entries = Changelog.get_entries()
    categories = Changelog.get_categories()
    category = Map.get(params, "category")

    entries =
      if is_nil(category), do: entries, else: Enum.filter(entries, &(&1.category == category))

    socket =
      socket
      |> assign(:entries, entries)
      |> assign(:categories, categories)
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

    entries =
      if is_nil(category), do: entries, else: Enum.filter(entries, &(&1.category == category))

    {:noreply,
     socket
     |> assign(:entries, entries)
     |> assign(
       :head_image,
       Tuist.Environment.app_url(path: "/marketing/images/og/changelog.jpg")
     )
     |> assign(:head_title, "Tuist Changelog")
     |> assign(:head_include_blog_rss_and_atom, false)
     |> assign(:head_include_changelog_rss_and_atom, true)
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign_structured_data(get_changelog_structured_data(entries))
     |> assign(
       :head_description,
       gettext(
         "Stay updated with the latest changes and improvements in Tuist. Read our changelog for detailed information about new features, bug fixes, and enhancements."
       )
     )}
  end
end
