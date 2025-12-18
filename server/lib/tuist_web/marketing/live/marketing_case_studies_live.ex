defmodule TuistWeb.Marketing.MarketingCaseStudiesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Marketing.StructuredMarkup

  alias Tuist.Marketing.CaseStudies

  on_mount {TuistWeb.Authentication, :mount_current_user}

  @cases_per_page 9

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:search_query, "")
      |> assign(:current_page, 1)
      |> assign(:total_pages, 1)
      |> assign(:filtered_cases, [])
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    all_cases = CaseStudies.get_cases()
    search_query = Map.get(params, "search", "")
    page = params |> Map.get("page", "1") |> String.to_integer()

    previous_page = Map.get(socket.assigns, :current_page, 1)
    page_changed = page != previous_page

    filtered_cases =
      if search_query == "" do
        all_cases
      else
        query_lower = String.downcase(search_query)

        Enum.filter(all_cases, fn case_study ->
          String.contains?(String.downcase(case_study.title), query_lower) ||
            String.contains?(String.downcase(case_study.name), query_lower) ||
            String.contains?(String.downcase(case_study.body), query_lower)
        end)
      end

    total_cases = length(filtered_cases)
    total_pages = max(ceil(total_cases / @cases_per_page), 1)
    page = min(max(page, 1), total_pages)
    start_index = (page - 1) * @cases_per_page
    paginated_cases = Enum.slice(filtered_cases, start_index, @cases_per_page)

    socket =
      socket
      |> assign(:filtered_cases, paginated_cases)
      |> assign(:search_query, search_query)
      |> assign(:current_page, page)
      |> assign(:total_pages, total_pages)
      |> assign(
        :head_image,
        Tuist.Environment.app_url(path: "/marketing/images/og/case-studies.jpg")
      )
      |> assign(:head_title, dgettext("marketing", "Case Studies"))
      |> assign(:head_include_case_studies_rss_and_atom, true)
      |> assign(:head_twitter_card, "summary_large_image")
      |> assign_structured_data(get_case_studies_structured_markup_data(all_cases))
      |> assign(
        :head_description,
        dgettext("marketing", "Learn how teams use Tuist to scale their iOS development.")
      )

    socket =
      if page_changed and socket.assigns[:live_action] != :mount do
        push_event(socket, "scroll-to-target", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => search_query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/case-studies?search=#{search_query}")}
  end

  def handle_event("page_change", %{"page" => page}, socket) do
    params = []

    params =
      if socket.assigns.search_query == "",
        do: params,
        else: ["search=#{URI.encode_www_form(socket.assigns.search_query)}" | params]

    params = ["page=#{page}" | params]
    query_string = "?#{Enum.join(params, "&")}"

    {:noreply, push_patch(socket, to: "/case-studies#{query_string}")}
  end

  defp get_case_studies_structured_markup_data(cases) do
    %{
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "name" => "Tuist Case Studies",
      "description" => "Learn how teams use Tuist to scale their iOS development.",
      "url" => Tuist.Environment.app_url(path: "/case-studies"),
      "mainEntity" => %{
        "@type" => "ItemList",
        "itemListElement" =>
          Enum.with_index(cases, fn case_study, index ->
            %{
              "@type" => "ListItem",
              "position" => index + 1,
              "url" => Tuist.Environment.app_url(path: case_study.slug),
              "name" => case_study.title
            }
          end)
      }
    }
  end
end
