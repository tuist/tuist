defmodule TuistWeb.RunDetailLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Runs.RanByBadge

  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Xcode
  alias TuistWeb.Utilities.Query

  @table_page_size 20

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_run: run}} = socket) do
    run = Tuist.Repo.preload(run, user: :account, project: :account)
    slug = Projects.get_project_slug_from_id(project.id)

    {:ok,
     socket
     |> assign(:run, run)
     |> assign(:head_title, "#{gettext("Run")} · #{slug} · Tuist")
     |> assign_initial_analytics_state()
     |> assign(:has_selective_testing_data, Xcode.has_selective_testing_data?(run))
     |> assign(:has_binary_cache_data, Xcode.has_binary_cache_data?(run))
     |> assign_async(:has_result_bundle, fn ->
       {:ok, %{has_result_bundle: CommandEvents.has_result_bundle?(run)}}
     end)}
  end

  def handle_params(params, _uri, socket) do
    uri = build_uri(params)
    selected_tab = selected_tab(params)

    socket =
      socket
      |> assign(:selected_tab, selected_tab)
      |> assign(:uri, uri)
      |> assign_tab_data(selected_tab, params)

    {:noreply, socket}
  end

  def handle_event("search-selective-testing", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/runs/#{socket.assigns.run.id}?#{Query.put(socket.assigns.uri.query, "selective-testing-filter", search)}"
      )

    {:noreply, socket}
  end

  def handle_event("search-binary-cache", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/runs/#{socket.assigns.run.id}?#{Query.put(socket.assigns.uri.query, "binary-cache-filter", search)}"
      )

    {:noreply, socket}
  end

  defp sort_test_modules(modules, "module", "asc") do
    Enum.sort_by(modules, & &1.name)
  end

  defp sort_test_modules(modules, "module", "desc") do
    Enum.sort_by(modules, & &1.name, :desc)
  end

  defp sort_test_modules(modules, "hash", "asc") do
    Enum.sort_by(modules, & &1.selective_testing_hit)
  end

  defp sort_test_modules(modules, "hash", "desc") do
    Enum.sort_by(modules, & &1.selective_testing_hit, :desc)
  end

  defp sort_test_modules(modules, _, _) do
    modules
  end

  defp sort_binary_cache_modules(modules, "module", "asc") do
    Enum.sort_by(modules, & &1.name)
  end

  defp sort_binary_cache_modules(modules, "module", "desc") do
    Enum.sort_by(modules, & &1.name, :desc)
  end

  defp sort_binary_cache_modules(modules, "hash", "asc") do
    Enum.sort_by(modules, & &1.selective_testing_hit)
  end

  defp sort_binary_cache_modules(modules, "hash", "desc") do
    Enum.sort_by(modules, & &1.selective_testing_hit, :desc)
  end

  defp sort_binary_cache_modules(modules, _, _) do
    modules
  end

  def sort_icon("desc") do
    "square_rounded_arrow_down"
  end

  def sort_icon("asc") do
    "square_rounded_arrow_up"
  end

  defp selected_tab(params) do
    tab = params["tab"]

    if is_nil(tab) do
      "overview"
    else
      tab
    end
  end

  def sort_order_patch_value(category, current_category, current_order) do
    if category == current_category do
      if current_order == "asc" do
        "desc"
      else
        "asc"
      end
    else
      "asc"
    end
  end

  defp assign_initial_analytics_state(socket) do
    socket
    |> assign(:selective_testing_analytics, %{})
    |> assign(:selective_testing_page_count, 0)
    |> assign(:binary_cache_analytics, %{})
    |> assign(:binary_cache_page_count, 0)
  end

  defp build_uri(params) do
    query_params = [
      "tab",
      "selective-testing-page",
      "selective-testing-sort-by",
      "selective-testing-sort-order",
      "binary-cache-page",
      "binary-cache-sort-by",
      "binary-cache-sort-order"
    ]

    URI.new!("?" <> URI.encode_query(Map.take(params, query_params)))
  end

  defp assign_tab_data(socket, "test-optimizations", params) do
    {analytics, page_count, current_modules} =
      load_selective_testing_data(socket.assigns.run, params)

    assign_selective_testing_data(socket, analytics, page_count, current_modules, params)
  end

  defp assign_tab_data(socket, "compilation-optimizations", params) do
    {analytics, page_count, current_modules} = load_binary_cache_data(socket.assigns.run, params)

    assign_binary_cache_data(socket, analytics, page_count, current_modules, params)
  end

  defp assign_tab_data(socket, _tab, params) do
    socket
    |> assign_selective_testing_defaults()
    |> assign_binary_cache_defaults()
    |> assign_param_defaults(params)
  end

  defp assign_selective_testing_data(socket, analytics, page_count, current_modules, params) do
    socket
    |> assign(:selective_testing_analytics, analytics)
    |> assign(:selective_testing_page_count, page_count)
    |> assign(:selective_testing_current_page_modules, current_modules)
    |> assign(:selective_testing_filter, params["selective-testing-filter"] || "")
    |> assign(:selective_testing_page, String.to_integer(params["selective-testing-page"] || "1"))
    |> assign(:selective_testing_sort_by, params["selective-testing-sort-by"] || "module")
    |> assign(:selective_testing_sort_order, params["selective-testing-sort-order"] || "desc")
  end

  defp assign_binary_cache_data(socket, analytics, page_count, current_modules, params) do
    socket
    |> assign(:binary_cache_analytics, analytics)
    |> assign(:binary_cache_page_count, page_count)
    |> assign(:binary_cache_current_page_modules, current_modules)
    |> assign(:binary_cache_filter, params["binary-cache-filter"] || "")
    |> assign(:binary_cache_page, String.to_integer(params["binary-cache-page"] || "1"))
    |> assign(:binary_cache_sort_by, params["binary-cache-sort-by"] || "module")
    |> assign(:binary_cache_sort_order, params["binary-cache-sort-order"] || "desc")
  end

  defp assign_selective_testing_defaults(socket) do
    socket
    |> assign(:selective_testing_analytics, socket.assigns.selective_testing_analytics)
    |> assign(:selective_testing_page_count, socket.assigns.selective_testing_page_count)
    |> assign(:selective_testing_current_page_modules, [])
  end

  defp assign_binary_cache_defaults(socket) do
    socket
    |> assign(:binary_cache_analytics, socket.assigns.binary_cache_analytics)
    |> assign(:binary_cache_page_count, socket.assigns.binary_cache_page_count)
    |> assign(:binary_cache_current_page_modules, [])
  end

  defp assign_param_defaults(socket, params) do
    socket
    |> assign(:selective_testing_filter, params["selective-testing-filter"] || "")
    |> assign(:selective_testing_page, String.to_integer(params["selective-testing-page"] || "1"))
    |> assign(:selective_testing_sort_by, params["selective-testing-sort-by"] || "module")
    |> assign(:selective_testing_sort_order, params["selective-testing-sort-order"] || "desc")
    |> assign(:binary_cache_filter, params["binary-cache-filter"] || "")
    |> assign(:binary_cache_page, String.to_integer(params["binary-cache-page"] || "1"))
    |> assign(:binary_cache_sort_by, params["binary-cache-sort-by"] || "module")
    |> assign(:binary_cache_sort_order, params["binary-cache-sort-order"] || "desc")
  end

  defp load_selective_testing_data(run, params) do
    analytics = Xcode.selective_testing_analytics(run)
    filter = params["selective-testing-filter"] || ""
    page = String.to_integer(params["selective-testing-page"] || "1")
    sort_by = params["selective-testing-sort-by"] || "module"
    sort_order = params["selective-testing-sort-order"] || "desc"

    filtered_modules = filter_modules_by_name(analytics.test_modules, filter)
    page_count = calculate_page_count(filtered_modules)

    current_modules =
      paginate_modules(filtered_modules, page, sort_by, sort_order, &sort_test_modules/3)

    {analytics, page_count, current_modules}
  end

  defp load_binary_cache_data(run, params) do
    analytics = Xcode.binary_cache_analytics(run)
    filter = params["binary-cache-filter"] || ""
    page = String.to_integer(params["binary-cache-page"] || "1")
    sort_by = params["binary-cache-sort-by"] || "module"
    sort_order = params["binary-cache-sort-order"] || "desc"

    filtered_modules = filter_modules_by_name(analytics.cacheable_targets, filter)
    page_count = calculate_page_count(filtered_modules)

    current_modules =
      paginate_modules(filtered_modules, page, sort_by, sort_order, &sort_binary_cache_modules/3)

    {analytics, page_count, current_modules}
  end

  defp filter_modules_by_name(modules, filter) do
    Enum.filter(modules, &String.contains?(String.downcase(&1.name), String.downcase(filter)))
  end

  defp calculate_page_count(modules) do
    max(div(length(modules), @table_page_size), 1)
  end

  defp paginate_modules(modules, page, sort_by, sort_order, sort_function) do
    modules
    |> sort_function.(sort_by, sort_order)
    |> Enum.slice((page - 1) * @table_page_size, @table_page_size)
  end
end
