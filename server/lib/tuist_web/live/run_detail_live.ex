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
    user =
      run
      |> CommandEvents.get_user_for_command_event(preload: :account)
      |> case do
        {:ok, user} -> user
        _ -> nil
      end

    slug = Projects.get_project_slug_from_id(project.id)

    {:ok,
     socket
     |> assign(:run, run)
     |> assign(:user, user)
     |> assign(:project, project)
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
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/runs/#{socket.assigns.run.id}?#{socket.assigns.uri.query |> Query.put("selective-testing-filter", search) |> Query.put("selective-testing-page", "1")}"
      )

    {:noreply, socket}
  end

  def handle_event("search-binary-cache", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/runs/#{socket.assigns.run.id}?#{socket.assigns.uri.query |> Query.put("binary-cache-filter", search) |> Query.put("binary-cache-page", "1")}"
      )

    {:noreply, socket}
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
      "selective-testing-filter",
      "binary-cache-page",
      "binary-cache-sort-by",
      "binary-cache-sort-order",
      "binary-cache-filter"
    ]

    URI.new!("?" <> URI.encode_query(Map.take(params, query_params)))
  end

  defp assign_tab_data(socket, "test-optimizations", params) do
    {analytics, meta} = load_selective_testing_data(socket.assigns.run, params)

    assign_selective_testing_data(socket, analytics, meta, params)
  end

  defp assign_tab_data(socket, "compilation-optimizations", params) do
    {analytics, meta} = load_binary_cache_data(socket.assigns.run, params)

    assign_binary_cache_data(socket, analytics, meta, params)
  end

  defp assign_tab_data(socket, _tab, params) do
    socket
    |> assign_selective_testing_defaults()
    |> assign_binary_cache_defaults()
    |> assign_param_defaults(params)
  end

  defp assign_selective_testing_data(socket, analytics, meta, params) do
    socket
    |> assign(:selective_testing_analytics, analytics)
    |> assign(:selective_testing_meta, meta)
    |> assign(:selective_testing_page_count, meta.total_pages)
    |> assign(:selective_testing_filter, params["selective-testing-filter"] || "")
    |> assign(:selective_testing_page, String.to_integer(params["selective-testing-page"] || "1"))
    |> assign(:selective_testing_sort_by, params["selective-testing-sort-by"] || "name")
    |> assign(:selective_testing_sort_order, params["selective-testing-sort-order"] || "asc")
  end

  defp assign_binary_cache_data(socket, analytics, meta, params) do
    socket
    |> assign(:binary_cache_analytics, analytics)
    |> assign(:binary_cache_meta, meta)
    |> assign(:binary_cache_page_count, meta.total_pages)
    |> assign(:binary_cache_filter, params["binary-cache-filter"] || "")
    |> assign(:binary_cache_page, String.to_integer(params["binary-cache-page"] || "1"))
    |> assign(:binary_cache_sort_by, params["binary-cache-sort-by"] || "name")
    |> assign(:binary_cache_sort_order, params["binary-cache-sort-order"] || "asc")
  end

  defp assign_selective_testing_defaults(socket) do
    socket
    |> assign(:selective_testing_analytics, socket.assigns.selective_testing_analytics)
    |> assign(:selective_testing_page_count, socket.assigns.selective_testing_page_count)
  end

  defp assign_binary_cache_defaults(socket) do
    socket
    |> assign(:binary_cache_analytics, socket.assigns.binary_cache_analytics)
    |> assign(:binary_cache_page_count, socket.assigns.binary_cache_page_count)
  end

  defp assign_param_defaults(socket, params) do
    socket
    |> assign(:selective_testing_filter, params["selective-testing-filter"] || "")
    |> assign(:selective_testing_page, String.to_integer(params["selective-testing-page"] || "1"))
    |> assign(:selective_testing_sort_by, params["selective-testing-sort-by"] || "name")
    |> assign(:selective_testing_sort_order, params["selective-testing-sort-order"] || "desc")
    |> assign(:binary_cache_filter, params["binary-cache-filter"] || "")
    |> assign(:binary_cache_page, String.to_integer(params["binary-cache-page"] || "1"))
    |> assign(:binary_cache_sort_by, params["binary-cache-sort-by"] || "name")
    |> assign(:binary_cache_sort_order, params["binary-cache-sort-order"] || "desc")
  end

  defp load_selective_testing_data(run, params) do
    counts = Xcode.selective_testing_counts(run)

    flop_params = %{
      filters: build_flop_filters(params["selective-testing-filter"]),
      page: String.to_integer(params["selective-testing-page"] || "1"),
      page_size: @table_page_size,
      order_by: [ensure_allowed_params("selective-testing-sort-by", params)],
      order_directions: [String.to_atom(params["selective-testing-sort-order"] || "asc")]
    }

    {filtered_analytics, meta} = Xcode.selective_testing_analytics(run, flop_params)

    analytics = Map.merge(filtered_analytics, counts)

    {analytics, meta}
  end

  defp load_binary_cache_data(run, params) do
    counts = Xcode.binary_cache_counts(run)

    flop_params = %{
      filters: build_flop_filters(params["binary-cache-filter"]),
      page: String.to_integer(params["binary-cache-page"] || "1"),
      page_size: @table_page_size,
      order_by: [ensure_allowed_params("binary-cache-sort-by", params)],
      order_directions: [String.to_atom(params["binary-cache-sort-order"] || "asc")]
    }

    {filtered_analytics, meta} = Xcode.binary_cache_analytics(run, flop_params)

    analytics = Map.merge(filtered_analytics, counts)

    {analytics, meta}
  end

  defp ensure_allowed_params("binary-cache-sort-by", %{"binary-cache-sort-by" => value}) when value in ["name"],
    do: String.to_existing_atom(value)

  defp ensure_allowed_params("binary-cache-sort-by", _value), do: :name

  defp ensure_allowed_params("selective-testing-sort-by", %{"selective-testing-sort-by" => value}) when value in ["name"],
    do: String.to_existing_atom(value)

  defp ensure_allowed_params("selective-testing-sort-by", _value), do: :name

  defp build_flop_filters(nil), do: []
  defp build_flop_filters(""), do: []

  defp build_flop_filters(filter_text) do
    [%{field: :name, op: :=~, value: filter_text}]
  end
end
