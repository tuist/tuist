defmodule TuistWeb.RunDetailLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Runs.CacheEndpointFormatter
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
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

    run = Tuist.ClickHouseRepo.preload(run, [:xcode_targets])
    slug = Projects.get_project_slug_from_id(project.id)

    {:ok,
     socket
     |> assign(:run, run)
     |> assign(:user, user)
     |> assign(:project, project)
     |> assign(:head_title, "#{dgettext("dashboard_builds", "Run")} · #{slug} · Tuist")
     |> assign_initial_analytics_state()
     |> assign(:available_filters, define_binary_cache_filters())
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

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params = Filter.Operations.add_filter_to_query(filter_id, socket)

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/runs/#{socket.assigns.run.id}?#{updated_params}"
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
         ~p"/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/runs/#{socket.assigns.run.id}?#{updated_query_params}"
     )
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event(
        "toggle-expand",
        %{"row-key" => target_name},
        %{assigns: %{expanded_target_names: expanded_target_names}} = socket
      ) do
    updated_expanded_names =
      if MapSet.member?(expanded_target_names, target_name) do
        MapSet.delete(expanded_target_names, target_name)
      else
        MapSet.put(expanded_target_names, target_name)
      end

    {:noreply, assign(socket, :expanded_target_names, updated_expanded_names)}
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
    |> assign(:binary_cache_active_filters, [])
    |> assign(:expanded_target_names, MapSet.new())
    |> assign(:binary_cache_json, "[]")
  end

  defp build_uri(params) do
    URI.new!("?" <> URI.encode_query(params))
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
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    socket
    |> assign(:binary_cache_analytics, analytics)
    |> assign(:binary_cache_meta, meta)
    |> assign(:binary_cache_page_count, meta.total_pages)
    |> assign(:binary_cache_filter, params["binary-cache-filter"] || "")
    |> assign(:binary_cache_active_filters, filters)
    |> assign(:binary_cache_page, String.to_integer(params["binary-cache-page"] || "1"))
    |> assign(:binary_cache_sort_by, params["binary-cache-sort-by"] || "name")
    |> assign(:binary_cache_sort_order, params["binary-cache-sort-order"] || "asc")
    |> assign(:binary_cache_json, binary_cache_targets_json(socket.assigns.run))
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
    |> assign(:binary_cache_active_filters, [])
  end

  defp assign_param_defaults(socket, params) do
    binary_cache_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    socket
    |> assign(:selective_testing_filter, params["selective-testing-filter"] || "")
    |> assign(:selective_testing_page, String.to_integer(params["selective-testing-page"] || "1"))
    |> assign(:selective_testing_sort_by, params["selective-testing-sort-by"] || "name")
    |> assign(:selective_testing_sort_order, params["selective-testing-sort-order"] || "desc")
    |> assign(:binary_cache_filter, params["binary-cache-filter"] || "")
    |> assign(:binary_cache_active_filters, binary_cache_filters)
    |> assign(:binary_cache_page, String.to_integer(params["binary-cache-page"] || "1"))
    |> assign(:binary_cache_sort_by, params["binary-cache-sort-by"] || "name")
    |> assign(:binary_cache_sort_order, params["binary-cache-sort-order"] || "desc")
  end

  defp load_selective_testing_data(run, params) do
    counts = Xcode.selective_testing_counts(run)

    flop_params = %{
      filters: build_text_flop_filters(params["selective-testing-filter"]),
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
    filters = Filter.Operations.decode_filters_from_query(params, define_binary_cache_filters())

    text_filters = build_text_flop_filters(params["binary-cache-filter"])
    filter_flop_filters = build_binary_cache_flop_filters(filters)

    flop_params = %{
      filters: text_filters ++ filter_flop_filters,
      page: String.to_integer(params["binary-cache-page"] || "1"),
      page_size: @table_page_size,
      order_by: [ensure_allowed_params("binary-cache-sort-by", params)],
      order_directions: [String.to_atom(params["binary-cache-sort-order"] || "asc")]
    }

    {filtered_analytics, meta} = Xcode.binary_cache_analytics(run, flop_params)

    analytics = Map.merge(filtered_analytics, counts)

    {analytics, meta}
  end

  defp binary_cache_targets_json(run) do
    run.xcode_targets
    |> Enum.filter(&(&1.binary_cache_hash != nil))
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&target_to_json_map/1)
    |> Jason.encode!(pretty: true)
  end

  defp target_to_json_map(target) do
    %{
      name: target.name,
      binary_cache_hit: target.binary_cache_hit,
      binary_cache_hash: target.binary_cache_hash,
      product: target.product,
      bundle_id: target.bundle_id,
      product_name: target.product_name,
      external_hash: target.external_hash,
      sources_hash: target.sources_hash,
      resources_hash: target.resources_hash,
      copy_files_hash: target.copy_files_hash,
      core_data_models_hash: target.core_data_models_hash,
      target_scripts_hash: target.target_scripts_hash,
      environment_hash: target.environment_hash,
      headers_hash: target.headers_hash,
      deployment_target_hash: target.deployment_target_hash,
      info_plist_hash: target.info_plist_hash,
      entitlements_hash: target.entitlements_hash,
      dependencies_hash: target.dependencies_hash,
      project_settings_hash: target.project_settings_hash,
      target_settings_hash: target.target_settings_hash,
      buildable_folders_hash: target.buildable_folders_hash,
      destinations: target.destinations,
      additional_strings: target.additional_strings
    }
    |> Enum.reject(fn {_k, v} -> empty_value?(v) end)
    |> Map.new()
  end

  defp empty_value?(nil), do: true
  defp empty_value?(""), do: true
  defp empty_value?([]), do: true
  defp empty_value?(_), do: false

  defp ensure_allowed_params("binary-cache-sort-by", %{"binary-cache-sort-by" => value}) when value in ["name"],
    do: String.to_existing_atom(value)

  defp ensure_allowed_params("binary-cache-sort-by", _value), do: :name

  defp ensure_allowed_params("selective-testing-sort-by", %{"selective-testing-sort-by" => value}) when value in ["name"],
    do: String.to_existing_atom(value)

  defp ensure_allowed_params("selective-testing-sort-by", _value), do: :name

  defp build_text_flop_filters(nil), do: []
  defp build_text_flop_filters(""), do: []

  defp build_text_flop_filters(filter_text) do
    [%{field: :name, op: :=~, value: filter_text}]
  end

  defp build_binary_cache_flop_filters(filters) do
    filters
    |> Enum.map(fn filter ->
      case filter.id do
        "binary_cache_hit" ->
          %{filter | value: if(filter.value, do: Atom.to_string(filter.value))}

        _ ->
          filter
      end
    end)
    |> Filter.Operations.convert_filters_to_flop()
  end

  defp define_binary_cache_filters do
    [
      %Filter.Filter{
        id: "binary_cache_hit",
        field: :binary_cache_hit,
        display_name: dgettext("dashboard_builds", "Hit"),
        type: :option,
        options: [:local, :remote, :miss],
        options_display_names: %{
          remote: dgettext("dashboard_builds", "Remote"),
          local: dgettext("dashboard_builds", "Local"),
          miss: dgettext("dashboard_builds", "Missed")
        },
        operator: :==,
        value: nil
      }
    ]
  end

  def cache_chart_border_radius(local_hits, remote_hits, misses, category) do
    has_local = local_hits > 0
    has_remote = remote_hits > 0
    has_misses = misses > 0

    case category do
      :local when has_local ->
        if not has_remote and not has_misses do
          [6, 6, 6, 6]
        else
          [6, 0, 0, 6]
        end

      :remote when has_remote ->
        cond do
          not has_local and not has_misses -> [6, 6, 6, 6]
          not has_local and has_misses -> [6, 0, 0, 6]
          has_local and not has_misses -> [0, 6, 6, 0]
          true -> [0, 0, 0, 0]
        end

      :misses when has_misses ->
        if not has_local and not has_remote do
          [6, 6, 6, 6]
        else
          [0, 6, 6, 0]
        end

      _ ->
        [0, 0, 0, 0]
    end
  end
end
