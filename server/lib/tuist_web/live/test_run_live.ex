defmodule TuistWeb.TestRunLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Runs
  alias Tuist.Xcode
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @table_page_size 20

  def mount(params, _session, %{assigns: %{selected_project: project}} = socket) do
    run =
      case Runs.get_test(params["test_run_id"], preload: [:ran_by_account, :build_run]) do
        {:ok, test} ->
          test

        {:error, :not_found} ->
          raise NotFoundError, dgettext("dashboard_tests", "Test run not found.")
      end

    if run.project_id != project.id do
      raise NotFoundError, dgettext("dashboard_tests", "Test run not found.")
    end

    slug = Projects.get_project_slug_from_id(project.id)

    project = Tuist.Repo.preload(project, :vcs_connection)

    run = Map.put(run, :project, project)

    command_event =
      case CommandEvents.get_command_event_by_test_run_id(run.id) do
        {:ok, event} -> event
        {:error, :not_found} -> nil
      end

    test_metrics = Runs.Analytics.get_test_run_metrics(run.id)
    failures_count = Runs.get_test_run_failures_count(run.id)

    socket =
      socket
      |> assign(:run, run)
      |> assign(:command_event, command_event)
      |> assign(:head_title, "#{dgettext("dashboard_tests", "Test Run")} · #{slug} · Tuist")
      |> assign(:test_metrics, test_metrics)
      |> assign(:failures_count, failures_count)
      |> assign_initial_analytics_state()
      |> assign_initial_test_cases_state()
      |> assign_initial_failures_state()
      |> assign(:available_filters, [])
      |> assign(:active_filters, [])
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
    selected_test_tab = params["test-tab"] || "test-cases"

    {available_filters, active_filters} =
      case {selected_tab, selected_test_tab} do
        {"overview", "test-cases"} ->
          {socket.assigns.test_cases_available_filters, socket.assigns.test_cases_active_filters}

        {"overview", "test-suites"} ->
          {socket.assigns.test_suites_available_filters, socket.assigns.test_suites_active_filters}

        {"overview", "test-modules"} ->
          {socket.assigns.test_modules_available_filters, socket.assigns.test_modules_active_filters}

        _ ->
          {[], []}
      end

    socket =
      socket
      |> assign(:selected_tab, selected_tab)
      |> assign(:uri, uri)
      |> assign(:available_filters, available_filters)
      |> assign(:active_filters, active_filters)
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

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/test-runs/#{socket.assigns.run.id}?#{updated_params}"
     )
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_query_params = Filter.Operations.update_filters_in_query(params, socket)

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/tests/test-runs/#{socket.assigns.run.id}?#{updated_query_params}"
     )
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
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
    |> assign(:test_cases_available_filters, define_test_cases_filters())
    |> assign(:test_cases_active_filters, [])
    |> assign(:test_suites, [])
    |> assign(:test_suites_meta, %{})
    |> assign(:test_suites_page, 1)
    |> assign(:test_suites_search, "")
    |> assign(:test_suites_sort_by, "name")
    |> assign(:test_suites_sort_order, "asc")
    |> assign(:test_suites_available_filters, define_test_suites_filters())
    |> assign(:test_suites_active_filters, [])
    |> assign(:test_modules, [])
    |> assign(:test_modules_meta, %{})
    |> assign(:test_modules_page, 1)
    |> assign(:test_modules_search, "")
    |> assign(:test_modules_sort_by, "name")
    |> assign(:test_modules_sort_order, "asc")
    |> assign(:test_modules_available_filters, define_test_modules_filters())
    |> assign(:test_modules_active_filters, [])
  end

  defp assign_initial_failures_state(socket) do
    socket
    |> assign(:failures, [])
    |> assign(:failures_meta, %{})
    |> assign(:failures_page, 1)
  end

  defp build_uri(params) do
    URI.new!("?" <> URI.encode_query(params))
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

    # Load failures data for the overview preview card
    {failures_grouped, failures_meta} = load_failures_data(socket.assigns.run, params)

    socket =
      socket
      |> assign(:selected_test_tab, selected_test_tab)
      |> assign(:failures_grouped_by_test_case, failures_grouped)
      |> assign(:failures_meta, failures_meta)
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

  defp assign_tab_data(socket, "failures", params) do
    {failures, meta} = load_failures_data(socket.assigns.run, params)
    assign_failures_data(socket, failures, meta, params)
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
    filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.test_cases_available_filters)

    socket
    |> assign(:test_cases, test_cases)
    |> assign(:test_cases_meta, meta)
    |> assign(:test_cases_filter, params["test-cases-filter"] || "")
    |> assign(:test_cases_page, String.to_integer(params["test-cases-page"] || "1"))
    |> assign(:test_cases_sort_by, params["test-cases-sort-by"] || "name")
    |> assign(:test_cases_sort_order, params["test-cases-sort-order"] || "asc")
    |> assign(:test_cases_active_filters, filters)
  end

  defp assign_test_suites_data(socket, test_suites, meta, params) do
    filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.test_suites_available_filters)

    socket
    |> assign(:test_suites, test_suites)
    |> assign(:test_suites_meta, meta)
    |> assign(:test_suites_filter, params["test-suites-filter"] || "")
    |> assign(:test_suites_page, String.to_integer(params["test-suites-page"] || "1"))
    |> assign(:test_suites_sort_by, params["test-suites-sort-by"] || "name")
    |> assign(:test_suites_sort_order, params["test-suites-sort-order"] || "asc")
    |> assign(:test_suites_active_filters, filters)
  end

  defp assign_test_modules_data(socket, test_modules, meta, params) do
    filters =
      Filter.Operations.decode_filters_from_query(params, socket.assigns.test_modules_available_filters)

    socket
    |> assign(:test_modules, test_modules)
    |> assign(:test_modules_meta, meta)
    |> assign(:test_modules_filter, params["test-modules-filter"] || "")
    |> assign(:test_modules_page, String.to_integer(params["test-modules-page"] || "1"))
    |> assign(:test_modules_sort_by, params["test-modules-sort-by"] || "name")
    |> assign(:test_modules_sort_order, params["test-modules-sort-order"] || "asc")
    |> assign(:test_modules_active_filters, filters)
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

  defp load_test_cases_data(run, params, available_filters \\ define_test_cases_filters()) do
    flop_params = %{
      filters: test_cases_filters(run, params, available_filters, params["test-cases-filter"]),
      page: String.to_integer(params["test-cases-page"] || "1"),
      page_size: @table_page_size,
      order_by: [ensure_allowed_test_cases_sort_params(params["test-cases-sort-by"])],
      order_directions: [String.to_atom(params["test-cases-sort-order"] || "asc")]
    }

    Runs.list_test_case_runs(flop_params)
  end

  defp load_test_suites_data(run, params, available_filters \\ define_test_suites_filters()) do
    flop_params = %{
      filters: test_suites_filters(run, params, available_filters, params["test-suites-filter"]),
      page: String.to_integer(params["test-suites-page"] || "1"),
      page_size: @table_page_size,
      order_by: [ensure_allowed_test_suites_sort_params(params["test-suites-sort-by"])],
      order_directions: [String.to_atom(params["test-suites-sort-order"] || "asc")]
    }

    Runs.list_test_suite_runs(flop_params)
  end

  defp load_test_modules_data(run, params, available_filters \\ define_test_modules_filters()) do
    flop_params = %{
      filters: test_modules_filters(run, params, available_filters, params["test-modules-filter"]),
      page: String.to_integer(params["test-modules-page"] || "1"),
      page_size: @table_page_size,
      order_by: [ensure_allowed_test_modules_sort_params(params["test-modules-sort-by"])],
      order_directions: [String.to_atom(params["test-modules-sort-order"] || "asc")]
    }

    Runs.list_test_module_runs(flop_params)
  end

  defp ensure_allowed_test_cases_sort_params(value) when value in ["name", "duration"], do: String.to_existing_atom(value)
  defp ensure_allowed_test_cases_sort_params(_value), do: :name

  defp ensure_allowed_test_suites_sort_params(value)
       when value in ["name", "duration", "avg_test_case_duration", "test_case_count"], do: String.to_existing_atom(value)

  defp ensure_allowed_test_suites_sort_params(_value), do: :name

  defp ensure_allowed_test_modules_sort_params(value)
       when value in ["name", "duration", "avg_test_case_duration", "test_case_count", "test_suite_count"],
       do: String.to_existing_atom(value)

  defp ensure_allowed_test_modules_sort_params(_value), do: :name

  defp load_failures_data(run, params) do
    page = String.to_integer(params["failures-page"] || "1")
    page_size = 30

    attrs = %{
      page: page,
      page_size: page_size,
      order_by: [:inserted_at],
      order_directions: [:desc]
    }

    {failures, meta} = Runs.list_test_run_failures(run.id, attrs)

    # Group failures by test case
    failures_grouped =
      Enum.group_by(failures, fn failure ->
        failure.test_case_run_id
      end)

    {failures_grouped, meta}
  end

  defp assign_failures_data(socket, failures_grouped, meta, params) do
    socket
    |> assign(:failures_grouped_by_test_case, failures_grouped)
    |> assign(:failures_meta, meta)
    |> assign(:failures_page, String.to_integer(params["failures-page"] || "1"))
  end

  defp test_cases_dropdown_item_patch_sort(sort_by, uri) do
    query_params = URI.decode_query(uri.query)
    current_sort_by = query_params["test-cases-sort-by"]
    current_sort_order = query_params["test-cases-sort-order"] || "asc"

    new_sort_order =
      if current_sort_by == sort_by do
        if current_sort_order == "asc", do: "desc", else: "asc"
      else
        if sort_by == "name", do: "asc", else: "desc"
      end

    "?#{uri.query |> Query.put("test-cases-sort-by", sort_by) |> Query.put("test-cases-sort-order", new_sort_order)}"
  end

  defp test_cases_column_patch_sort(assigns, sort_by) do
    current_sort_order = assigns.test_cases_sort_order
    new_sort_order = if current_sort_order == "asc", do: "desc", else: "asc"

    "?#{assigns.uri.query |> Query.put("test-cases-sort-by", sort_by) |> Query.put("test-cases-sort-order", new_sort_order)}"
  end

  defp test_suites_dropdown_item_patch_sort(sort_by, uri) do
    query_params = URI.decode_query(uri.query)
    current_sort_by = query_params["test-suites-sort-by"]
    current_sort_order = query_params["test-suites-sort-order"] || "asc"

    new_sort_order =
      if current_sort_by == sort_by do
        if current_sort_order == "asc", do: "desc", else: "asc"
      else
        if sort_by == "name", do: "asc", else: "desc"
      end

    "?#{uri.query |> Query.put("test-suites-sort-by", sort_by) |> Query.put("test-suites-sort-order", new_sort_order)}"
  end

  defp test_suites_column_patch_sort(assigns, sort_by) do
    current_sort_order = assigns.test_suites_sort_order
    new_sort_order = if current_sort_order == "asc", do: "desc", else: "asc"

    "?#{assigns.uri.query |> Query.put("test-suites-sort-by", sort_by) |> Query.put("test-suites-sort-order", new_sort_order)}"
  end

  defp test_modules_dropdown_item_patch_sort(sort_by, uri) do
    query_params = URI.decode_query(uri.query)
    current_sort_by = query_params["test-modules-sort-by"]
    current_sort_order = query_params["test-modules-sort-order"] || "asc"

    new_sort_order =
      if current_sort_by == sort_by do
        if current_sort_order == "asc", do: "desc", else: "asc"
      else
        if sort_by == "name", do: "asc", else: "desc"
      end

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

  defp test_cases_filters(run, params, available_filters, search) do
    base_filters =
      [%{field: :test_run_id, op: :==, value: run.id}] ++
        (params
         |> Filter.Operations.decode_filters_from_query(available_filters)
         |> Filter.Operations.convert_filters_to_flop()
         |> Enum.map(&remap_test_case_filter_fields/1)
         |> map_filter_status_value())

    if search && search != "" do
      base_filters ++ [%{field: :name, op: :=~, value: search}]
    else
      base_filters
    end
  end

  defp test_suites_filters(run, params, available_filters, search) do
    base_filters =
      [%{field: :test_run_id, op: :==, value: run.id}] ++
        (params
         |> Filter.Operations.decode_filters_from_query(available_filters)
         |> Filter.Operations.convert_filters_to_flop()
         |> Enum.map(&remap_test_suite_filter_fields/1)
         |> map_filter_status_value())

    if search && search != "" do
      base_filters ++ [%{field: :name, op: :=~, value: search}]
    else
      base_filters
    end
  end

  defp test_modules_filters(run, params, available_filters, search) do
    base_filters =
      [%{field: :test_run_id, op: :==, value: run.id}] ++
        (params
         |> Filter.Operations.decode_filters_from_query(available_filters)
         |> Filter.Operations.convert_filters_to_flop()
         |> Enum.map(&remap_test_module_filter_fields/1)
         |> map_filter_status_value())

    if search && search != "" do
      base_filters ++ [%{field: :name, op: :=~, value: search}]
    else
      base_filters
    end
  end

  defp map_filter_status_value(filters) do
    Enum.map(filters, fn filter ->
      if filter.field == :status do
        %{filter | value: filter.value}
      else
        filter
      end
    end)
  end

  defp remap_test_case_filter_fields(%{field: :test_case_duration} = filter), do: %{filter | field: :duration}
  defp remap_test_case_filter_fields(%{field: :test_case_status} = filter), do: %{filter | field: :status}
  defp remap_test_case_filter_fields(filter), do: filter

  defp remap_test_suite_filter_fields(%{field: :test_suite_test_case_count} = filter),
    do: %{filter | field: :test_case_count}

  defp remap_test_suite_filter_fields(%{field: :test_suite_avg_test_case_duration} = filter),
    do: %{filter | field: :avg_test_case_duration}

  defp remap_test_suite_filter_fields(%{field: :test_suite_duration} = filter), do: %{filter | field: :duration}
  defp remap_test_suite_filter_fields(%{field: :test_suite_status} = filter), do: %{filter | field: :status}
  defp remap_test_suite_filter_fields(filter), do: filter

  defp remap_test_module_filter_fields(%{field: :test_module_test_suite_count} = filter),
    do: %{filter | field: :test_suite_count}

  defp remap_test_module_filter_fields(%{field: :test_module_test_case_count} = filter),
    do: %{filter | field: :test_case_count}

  defp remap_test_module_filter_fields(%{field: :test_module_avg_test_case_duration} = filter),
    do: %{filter | field: :avg_test_case_duration}

  defp remap_test_module_filter_fields(%{field: :test_module_duration} = filter), do: %{filter | field: :duration}
  defp remap_test_module_filter_fields(%{field: :test_module_status} = filter), do: %{filter | field: :status}
  defp remap_test_module_filter_fields(filter), do: filter

  defp define_test_cases_filters do
    [
      %Filter.Filter{
        id: "test_case_duration",
        field: :test_case_duration,
        display_name: dgettext("dashboard_tests", "Duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "test_case_status",
        field: :test_case_status,
        display_name: dgettext("dashboard_tests", "Status"),
        type: :option,
        options: ["success", "failure", "skipped"],
        options_display_names: %{
          "success" => dgettext("dashboard_tests", "Passed"),
          "failure" => dgettext("dashboard_tests", "Failed"),
          "skipped" => dgettext("dashboard_tests", "Skipped")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  defp define_test_suites_filters do
    [
      %Filter.Filter{
        id: "test_suite_test_case_count",
        field: :test_suite_test_case_count,
        display_name: dgettext("dashboard_tests", "Test cases"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "test_suite_avg_test_case_duration",
        field: :test_suite_avg_test_case_duration,
        display_name: dgettext("dashboard_tests", "Avg. test case duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "test_suite_duration",
        field: :test_suite_duration,
        display_name: dgettext("dashboard_tests", "Duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "test_suite_status",
        field: :test_suite_status,
        display_name: dgettext("dashboard_tests", "Status"),
        type: :option,
        options: ["success", "failure", "skipped"],
        options_display_names: %{
          "success" => dgettext("dashboard_tests", "Passed"),
          "failure" => dgettext("dashboard_tests", "Failed"),
          "skipped" => dgettext("dashboard_tests", "Skipped")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  defp define_test_modules_filters do
    [
      %Filter.Filter{
        id: "test_module_test_suite_count",
        field: :test_module_test_suite_count,
        display_name: dgettext("dashboard_tests", "Test suites"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "test_module_test_case_count",
        field: :test_module_test_case_count,
        display_name: dgettext("dashboard_tests", "Test cases"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "test_module_avg_test_case_duration",
        field: :test_module_avg_test_case_duration,
        display_name: dgettext("dashboard_tests", "Avg. test case duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "test_module_duration",
        field: :test_module_duration,
        display_name: dgettext("dashboard_tests", "Duration"),
        type: :number,
        operator: :>,
        value: ""
      },
      %Filter.Filter{
        id: "test_module_status",
        field: :test_module_status,
        display_name: dgettext("dashboard_tests", "Status"),
        type: :option,
        options: ["success", "failure"],
        options_display_names: %{
          "success" => dgettext("dashboard_tests", "Passed"),
          "failure" => dgettext("dashboard_tests", "Failed")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  def format_failure_message(failure, run) do
    message =
      case {failure.path, failure.issue_type, failure.message} do
        # No path cases
        {nil, "assertion_failure", nil} ->
          dgettext("dashboard_tests", "Expectation failed")

        {nil, "assertion_failure", message} ->
          dgettext("dashboard_tests", "Expectation failed: %{message}", message: message)

        {nil, "error_thrown", nil} ->
          dgettext("dashboard_tests", "Caught error")

        {nil, "error_thrown", message} ->
          dgettext("dashboard_tests", "Caught error: %{message}", message: message)

        {nil, "issue_recorded", nil} ->
          dgettext("dashboard_tests", "Issue recorded")

        {nil, "issue_recorded", message} ->
          dgettext("dashboard_tests", "Issue recorded: %{message}", message: message)

        {nil, _, nil} ->
          dgettext("dashboard_tests", "Unknown error")

        {nil, _, message} ->
          message

        # Has path cases
        {path, "assertion_failure", nil} ->
          dgettext("dashboard_tests", "Expectation failed at %{location}", location: "#{path}:#{failure.line_number}")

        {path, "assertion_failure", message} ->
          dgettext("dashboard_tests", "Expectation failed at %{location}: %{message}",
            location: "#{path}:#{failure.line_number}",
            message: message
          )

        {path, "error_thrown", nil} ->
          dgettext("dashboard_tests", "Caught error at %{location}", location: "#{path}:#{failure.line_number}")

        {path, "error_thrown", message} ->
          dgettext("dashboard_tests", "Caught error at %{location}: %{message}",
            location: "#{path}:#{failure.line_number}",
            message: message
          )

        {path, "issue_recorded", nil} ->
          dgettext("dashboard_tests", "Issue recorded at %{location}", location: "#{path}:#{failure.line_number}")

        {path, "issue_recorded", message} ->
          dgettext("dashboard_tests", "Issue recorded at %{location}: %{message}",
            location: "#{path}:#{failure.line_number}",
            message: message
          )

        {path, _, nil} ->
          "#{path}:#{failure.line_number}"

        {path, _, message} ->
          "#{path}:#{failure.line_number}: #{message}"
      end

    linkify_failure_location(message, failure, run)
  end

  defp linkify_failure_location(message, failure, run) do
    if not is_nil(failure.path) and has_github_vcs?(run) do
      location_text = "#{failure.path}:#{failure.line_number}"

      location_link =
        ~s(<a href="https://github.com/#{run.project.vcs_connection.repository_full_handle}/blob/#{run.git_commit_sha}/#{failure.path}#L#{failure.line_number}" target="_blank">#{location_text}</a>)

      message
      |> String.replace(location_text, location_link)
      |> raw()
    else
      message
    end
  end

  defp has_github_vcs?(run) do
    not is_nil(run.project.vcs_connection) and
      run.project.vcs_connection.provider == :github and
      not is_nil(run.git_commit_sha)
  end
end
