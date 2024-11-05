defmodule TuistWeb.MarketingChangelogLive do
  use TuistWeb, :live_view

  def mount(params, _session, socket) do
    entries = Tuist.Changelog.get_entries()
    categories = Tuist.Changelog.get_categories()
    category = params |> Map.get("category")

    entries =
      if is_nil(category), do: entries, else: entries |> Enum.filter(&(&1.category == category))

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
    entries = Tuist.Changelog.get_entries()
    category = params |> Map.get("category")

    entries =
      if is_nil(category), do: entries, else: entries |> Enum.filter(&(&1.category == category))

    page_structured_data =
      %{
        "@context" => "https://schema.org",
        "@type" => "ItemList",
        "name" => "Changelog",
        "description" => "Stay updated with the latest changes and improvements in Tuist.",
        "publisher" => TuistWeb.StructuredMarkup.get_organization(),
        "itemListElement" =>
          entries
          |> Enum.with_index()
          |> Enum.map(fn {entry, index} ->
            %{
              "@type" => "ListItem",
              "position" => index + 1,
              "item" => %{
                "@type" => "Article",
                "headline" => entry.title,
                "datePublished" => entry.date |> Timex.format!("{ISO:Extended}"),
                "url" => Tuist.Environment.app_url(path: "/changelog##{entry.id}"),
                "articleSection" => entry.category,
                "description" => entry.body
              }
            }
          end)
      }
      |> Jason.encode!()

    {:noreply,
     socket
     |> assign(:entries, entries)
     |> assign(:head_image, Tuist.Environment.app_url(path: "/images/marketing/og/changelog.jpg"))
     |> assign(:head_title, "Changelog · Tuist")
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(:head_structured_data, page_structured_data)
     |> assign(
       :head_description,
       gettext(
         "Stay updated with the latest changes and improvements in Tuist. Read our changelog for detailed information about new features, bug fixes, and enhancements."
       )
     )}
  end
end
