defmodule TuistWeb.TestRunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Runs.RanByBadge

  alias Tuist.Accounts
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Runs
  alias Tuist.Xcode
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @table_page_size 20

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    run =
      case Runs.get_test(params["test_run_id"]) do
        {:ok, test} ->
          test

        {:error, :not_found} ->
          raise NotFoundError, gettext("Test run not found.")
      end

    slug = Projects.get_project_slug_from_id(project.id)

    # Fetch the account that ran this test and put it into the run
    ran_by_account =
      if run.account_id do
        Accounts.get_account_by_id(run.account_id)
      end

    run = Map.put(run, :ran_by_account, ran_by_account)

    command_event =
      case CommandEvents.get_command_event_by_test_run_id(run.id) do
        {:ok, event} -> event
        {:error, :not_found} -> nil
      end

    if run.project_id != project.id do
      raise NotFoundError, gettext("Test run not found.")
    end

    socket =
      socket
      |> assign(:run, run)
      |> assign(:command_event, command_event)
      |> assign(:head_title, "#{gettext("Test Run")} · #{slug} · Tuist")
      |> assign_initial_analytics_state()
      |> assign_initial_test_cases_state()
      |> assign(:has_selective_testing_data, command_event && Xcode.has_selective_testing_data?(command_event))
      |> assign(:has_binary_cache_data, command_event && Xcode.has_binary_cache_data?(command_event))
      |> assign_async(:has_result_bundle, fn ->
        {:ok, %{has_result_bundle: (command_event && CommandEvents.has_result_bundle?(command_event)) || false}}
      end)

    {:ok, socket}
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
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/tests/test-runs/#{socket.assigns.run.id}?#{socket.assigns.uri.query |> Query.put("selective-testing-filter", search) |> Query.put("selective-testing-page", "1")}"
      )

    {:noreply, socket}
  end

  def handle_event("search-binary-cache", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/tests/test-runs/#{socket.assigns.run.id}?#{socket.assigns.uri.query |> Query.put("binary-cache-filter", search) |> Query.put("binary-cache-page", "1")}"
      )

    {:noreply, socket}
  end

  def handle_event("search-test-cases", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/tests/test-runs/#{socket.assigns.run.id}?#{socket.assigns.uri.query |> Query.put("test-cases-filter", search) |> Query.put("test-cases-page", "1")}"
      )

    {:noreply, socket}
  end

  def handle_event("search-test-suites", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/tests/test-runs/#{socket.assigns.run.id}?#{socket.assigns.uri.query |> Query.put("test-suites-filter", search) |> Query.put("test-suites-page", "1")}"
      )

    {:noreply, socket}
  end

  def handle_event("search-test-modules", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/tests/test-runs/#{socket.assigns.run.id}?#{socket.assigns.uri.query |> Query.put("test-modules-filter", search) |> Query.put("test-modules-page", "1")}"
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

  defp assign_initial_test_cases_state(socket) do
    socket
    |> assign(:selected_test_tab, "test-cases")
    |> assign(:test_cases, [])
    |> assign(:test_cases_meta, %{})
    |> assign(:test_cases_page, 1)
    |> assign(:test_cases_search, "")
    |> assign(:test_cases_sort_by, "name")
    |> assign(:test_cases_sort_order, "asc")
    |> assign(:test_suites, [])
    |> assign(:test_suites_meta, %{})
    |> assign(:test_suites_page, 1)
    |> assign(:test_suites_search, "")
    |> assign(:test_suites_sort_by, "name")
    |> assign(:test_suites_sort_order, "asc")
    |> assign(:test_modules, [])
    |> assign(:test_modules_meta, %{})
    |> assign(:test_modules_page, 1)
    |> assign(:test_modules_search, "")
    |> assign(:test_modules_sort_by, "name")
    |> assign(:test_modules_sort_order, "asc")
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
      "binary-cache-filter",
      "test-tab",
      "test-cases-page",
      "test-cases-sort-by",
      "test-cases-sort-order",
      "test-cases-filter",
      "test-suites-page",
      "test-suites-sort-by",
      "test-suites-sort-order",
      "test-suites-filter",
      "test-modules-page",
      "test-modules-sort-by",
      "test-modules-sort-order",
      "test-modules-filter"
    ]

    URI.new!("?" <> URI.encode_query(Map.take(params, query_params)))
  end

  defp assign_tab_data(socket, "test-optimizations", params) do
    if socket.assigns.command_event do
      {analytics, meta} = load_selective_testing_data(socket.assigns.command_event, params)
      assign_selective_testing_data(socket, analytics, meta, params)
    else
      socket |> assign_selective_testing_defaults() |> assign_param_defaults(params)
    end
  end

  defp assign_tab_data(socket, "compilation-optimizations", params) do
    if socket.assigns.command_event do
      {analytics, meta} = load_binary_cache_data(socket.assigns.command_event, params)
      assign_binary_cache_data(socket, analytics, meta, params)
    else
      socket |> assign_binary_cache_defaults() |> assign_param_defaults(params)
    end
  end

  defp assign_tab_data(socket, "overview", params) do
    selected_test_tab = params["test-tab"] || "test-cases"

    socket =
      socket
      |> assign(:selected_test_tab, selected_test_tab)
      |> assign_selective_testing_defaults()
      |> assign_binary_cache_defaults()
      |> assign_param_defaults(params)

    case selected_test_tab do
      "test-cases" ->
        {test_cases, meta} = load_test_cases_data(socket.assigns.run, params)
        assign_test_cases_data(socket, test_cases, meta, params)

      "test-suites" ->
        {test_suites, meta} = load_test_suites_data(socket.assigns.run, params)
        assign_test_suites_data(socket, test_suites, meta, params)

      "test-modules" ->
        {test_modules, meta} = load_test_modules_data(socket.assigns.run, params)
        assign_test_modules_data(socket, test_modules, meta, params)

      _ ->
        {test_cases, meta} = load_test_cases_data(socket.assigns.run, params)
        assign_test_cases_data(socket, test_cases, meta, params)
    end
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

  defp assign_test_cases_data(socket, test_cases, meta, params) do
    socket
    |> assign(:test_cases, test_cases)
    |> assign(:test_cases_meta, meta)
    |> assign(:test_cases_filter, params["test-cases-filter"] || "")
    |> assign(:test_cases_page, String.to_integer(params["test-cases-page"] || "1"))
    |> assign(:test_cases_sort_by, params["test-cases-sort-by"] || "name")
    |> assign(:test_cases_sort_order, params["test-cases-sort-order"] || "asc")
  end

  defp assign_test_suites_data(socket, test_suites, meta, params) do
    socket
    |> assign(:test_suites, test_suites)
    |> assign(:test_suites_meta, meta)
    |> assign(:test_suites_filter, params["test-suites-filter"] || "")
    |> assign(:test_suites_page, String.to_integer(params["test-suites-page"] || "1"))
    |> assign(:test_suites_sort_by, params["test-suites-sort-by"] || "name")
    |> assign(:test_suites_sort_order, params["test-suites-sort-order"] || "asc")
  end

  defp assign_test_modules_data(socket, test_modules, meta, params) do
    socket
    |> assign(:test_modules, test_modules)
    |> assign(:test_modules_meta, meta)
    |> assign(:test_modules_filter, params["test-modules-filter"] || "")
    |> assign(:test_modules_page, String.to_integer(params["test-modules-page"] || "1"))
    |> assign(:test_modules_sort_by, params["test-modules-sort-by"] || "name")
    |> assign(:test_modules_sort_order, params["test-modules-sort-order"] || "asc")
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
    |> assign(:test_cases_filter, params["test-cases-filter"] || "")
    |> assign(:test_cases_page, String.to_integer(params["test-cases-page"] || "1"))
    |> assign(:test_cases_sort_by, params["test-cases-sort-by"] || "name")
    |> assign(:test_cases_sort_order, params["test-cases-sort-order"] || "asc")
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

  defp load_test_cases_data(run, params) do
    flop_params = %{
      filters: [
        %{field: :test_run_id, op: :==, value: run.id}
        | build_flop_filters(params["test-cases-filter"])
      ],
      page: String.to_integer(params["test-cases-page"] || "1"),
      page_size: @table_page_size,
      order_by: [ensure_allowed_test_cases_sort_params(params["test-cases-sort-by"])],
      order_directions: [String.to_atom(params["test-cases-sort-order"] || "asc")]
    }

    Runs.list_test_case_runs(flop_params)
  end

  defp load_test_suites_data(run, params) do
    flop_params = %{
      filters: [
        %{field: :test_run_id, op: :==, value: run.id}
        | build_flop_filters(params["test-suites-filter"])
      ],
      page: String.to_integer(params["test-suites-page"] || "1"),
      page_size: @table_page_size,
      order_by: [ensure_allowed_test_suites_sort_params(params["test-suites-sort-by"])],
      order_directions: [String.to_atom(params["test-suites-sort-order"] || "asc")]
    }

    Runs.list_test_suite_runs(flop_params)
  end

  defp load_test_modules_data(run, params) do
    flop_params = %{
      filters: [
        %{field: :test_run_id, op: :==, value: run.id}
        | build_flop_filters(params["test-modules-filter"])
      ],
      page: String.to_integer(params["test-modules-page"] || "1"),
      page_size: @table_page_size,
      order_by: [ensure_allowed_test_modules_sort_params(params["test-modules-sort-by"])],
      order_directions: [String.to_atom(params["test-modules-sort-order"] || "asc")]
    }

    Runs.list_test_module_runs(flop_params)
  end

  defp ensure_allowed_test_cases_sort_params(value) when value in ["name", "duration"], do: String.to_existing_atom(value)
  defp ensure_allowed_test_cases_sort_params(_value), do: :name

  defp ensure_allowed_test_suites_sort_params(value) when value in ["name", "duration"],
    do: String.to_existing_atom(value)

  defp ensure_allowed_test_suites_sort_params(_value), do: :name

  defp ensure_allowed_test_modules_sort_params(value) when value in ["name", "duration"],
    do: String.to_existing_atom(value)

  defp ensure_allowed_test_modules_sort_params(_value), do: :name

  defp test_cases_dropdown_item_patch_sort(sort_by, uri) do
    query_params = URI.decode_query(uri.query)
    current_sort_order = query_params["test-cases-sort-order"] || "asc"

    new_sort_order =
      if query_params["test-cases-sort-by"] == sort_by && current_sort_order == "asc", do: "desc", else: "asc"

    "?#{uri.query |> Query.put("test-cases-sort-by", sort_by) |> Query.put("test-cases-sort-order", new_sort_order)}"
  end

  defp test_cases_column_patch_sort(assigns, sort_by) do
    current_sort_order = assigns.test_cases_sort_order
    new_sort_order = if current_sort_order == "asc", do: "desc", else: "asc"

    "?#{assigns.uri.query |> Query.put("test-cases-sort-by", sort_by) |> Query.put("test-cases-sort-order", new_sort_order)}"
  end

  defp test_suites_dropdown_item_patch_sort(sort_by, uri) do
    query_params = URI.decode_query(uri.query)
    current_sort_order = query_params["test-suites-sort-order"] || "asc"

    new_sort_order =
      if query_params["test-suites-sort-by"] == sort_by && current_sort_order == "asc", do: "desc", else: "asc"

    "?#{uri.query |> Query.put("test-suites-sort-by", sort_by) |> Query.put("test-suites-sort-order", new_sort_order)}"
  end

  defp test_suites_column_patch_sort(assigns, sort_by) do
    current_sort_order = assigns.test_suites_sort_order
    new_sort_order = if current_sort_order == "asc", do: "desc", else: "asc"

    "?#{assigns.uri.query |> Query.put("test-suites-sort-by", sort_by) |> Query.put("test-suites-sort-order", new_sort_order)}"
  end

  defp test_modules_dropdown_item_patch_sort(sort_by, uri) do
    query_params = URI.decode_query(uri.query)
    current_sort_order = query_params["test-modules-sort-order"] || "asc"

    new_sort_order =
      if query_params["test-modules-sort-by"] == sort_by && current_sort_order == "asc", do: "desc", else: "asc"

    "?#{uri.query |> Query.put("test-modules-sort-by", sort_by) |> Query.put("test-modules-sort-order", new_sort_order)}"
  end

  defp test_modules_column_patch_sort(assigns, sort_by) do
    current_sort_order = assigns.test_modules_sort_order
    new_sort_order = if current_sort_order == "asc", do: "desc", else: "asc"

    "?#{assigns.uri.query |> Query.put("test-modules-sort-by", sort_by) |> Query.put("test-modules-sort-order", new_sort_order)}"
  end

  defp build_flop_filters(nil), do: []
  defp build_flop_filters(""), do: []

  defp build_flop_filters(filter_text) do
    [%{field: :name, op: :=~, value: filter_text}]
  end
end
