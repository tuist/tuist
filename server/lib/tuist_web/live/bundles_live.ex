defmodule TuistWeb.BundlesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.EmptyState
  import TuistWeb.Previews.PlatformTag

  alias Noora.Filter
  alias Tuist.Bundles
  alias Tuist.Projects
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA

  def mount(_params, _session, %{assigns: %{selected_project: project}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_cache", "Bundles")} · #{Projects.get_project_slug_from_id(project.id)} · Tuist"
      )
      |> assign(:available_filters, define_filters(project))

    {:ok, socket}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: project}} = socket) do
    uri = URI.new!("?" <> URI.encode_query(params))

    bundles_sort_order = params["bundles-sort-order"] || "desc"
    bundles_sort_by = params["bundles-sort-by"] || "created-at"
    bundles_type = params["bundles-type"] || "any"

    params =
      if not Map.has_key?(socket.assigns, :current_params) and Query.has_cursor?(params) do
        Query.clear_cursors(params)
      else
        params
      end

    bundle_size_apps = Bundles.distinct_project_app_bundles(project)
    bundle_size_selected_app = params["bundle-size-app"] || Bundles.default_app(project)

    bundle_size_branch =
      case params["bundle-size-branch"] do
        "any" -> "any"
        _ -> "default-branch"
      end

    bundle_size_selected_widget = params["bundle-size-selected-widget"] || "install-size"

    %{preset: preset, period: {bundle_start_date, _} = period} =
      DatePicker.date_picker_params(params, "bundle-size")

    {
      :noreply,
      socket
      |> assign(
        :uri,
        uri
      )
      |> assign(:current_params, params)
      |> assign(:bundles_sort_by, bundles_sort_by)
      |> assign(:bundles_sort_order, bundles_sort_order)
      |> assign(:bundles_type, bundles_type)
      |> assign(:bundle_size_selected_app, bundle_size_selected_app)
      |> assign(:bundle_size_apps, Enum.map(bundle_size_apps, & &1.name))
      |> assign(:bundle_size_preset, preset)
      |> assign(:bundle_size_period, period)
      |> assign(:bundle_size_branch, bundle_size_branch)
      |> assign(
        :bundle_size_last_bundle,
        Bundles.last_project_bundle(project,
          name: bundle_size_selected_app,
          git_branch: bundle_size_git_branch(bundle_size_branch, project),
          type: string_to_bundle_type(bundles_type)
        )
      )
      |> assign(
        :bundle_size_previous_bundle,
        Bundles.last_project_bundle(project,
          name: bundle_size_selected_app,
          inserted_before: bundle_start_date,
          git_branch: bundle_size_git_branch(bundle_size_branch, project),
          type: string_to_bundle_type(bundles_type)
        )
      )
      |> assign(:bundle_size_selected_widget, bundle_size_selected_widget)
      |> assign(:show_branch_dropdown, Bundles.has_bundles_in_project_default_branch?(project))
      |> assign(:has_any_bundles, Bundles.has_bundles_in_project?(project))
      |> assign_bundle_size_analytics()
      |> assign_bundles(params)
    }
  end

  # Returns actual git branch based on the branch dropdown value.
  defp bundle_size_git_branch(bundle_size_branch, project) do
    case bundle_size_branch do
      "default-branch" -> project.default_branch
      value -> value
    end
  end

  defp assign_bundles(
         %{
           assigns: %{
             selected_project: project,
             bundles_sort_by: bundles_sort_by,
             bundles_sort_order: bundles_sort_order,
             available_filters: available_filters
           }
         } = socket,
         params
       ) do
    filters = Filter.Operations.decode_filters_from_query(params, available_filters)

    base_flop_filters = [
      %{field: :project_id, op: :==, value: project.id}
    ]

    filter_flop_filters = build_flop_filters(filters)
    flop_filters = base_flop_filters ++ filter_flop_filters

    order_by =
      case bundles_sort_by do
        "created-at" -> :inserted_at
        "install-size" -> :install_size
        "download-size" -> :download_size
      end

    order_direction = String.to_atom(bundles_sort_order)

    options = %{
      filters: flop_filters,
      order_by: [order_by],
      order_directions: [order_direction]
    }

    options =
      cond do
        !is_nil(params["after"]) ->
          options
          |> Map.put(:first, 20)
          |> Map.put(:after, params["after"])

        !is_nil(params["before"]) ->
          options
          |> Map.put(:last, 20)
          |> Map.put(:before, params["before"])

        true ->
          Map.put(options, :first, 20)
      end

    {next_bundles, next_bundles_meta} = Bundles.list_bundles(options)

    socket
    |> assign(:active_filters, filters)
    |> assign(:bundles, next_bundles)
    |> assign(:bundles_meta, next_bundles_meta)
  end

  defp build_flop_filters(filters) do
    size_filters =
      filters
      |> Enum.filter(fn filter -> filter.field in [:install_size, :download_size] end)
      |> Enum.filter(fn filter -> not is_nil(filter.value) and filter.value != "" end)
      |> Enum.map(fn filter ->
        # Convert MB to bytes (multiply by 1,048,576)
        mb_value = String.to_integer(filter.value)

        value_in_bytes = mb_value * 1_048_576
        %{field: filter.field, op: filter.operator, value: value_in_bytes}
      end)

    platform_filters =
      filters
      |> Enum.filter(fn filter -> filter.field == :supported_platforms end)
      |> Enum.filter(fn filter -> not is_nil(filter.value) and filter.value != "" end)
      |> Enum.map(fn filter ->
        %{field: filter.field, op: :contains, value: filter.value}
      end)

    other_filters =
      filters
      |> Enum.reject(fn filter -> filter.field in [:install_size, :download_size, :supported_platforms] end)
      |> Filter.Operations.convert_filters_to_flop()

    size_filters ++ platform_filters ++ other_filters
  end

  defp assign_bundle_size_analytics(
         %{
           assigns: %{
             selected_project: project,
             bundle_size_selected_widget: bundle_size_selected_widget,
             bundle_size_branch: bundle_size_branch,
             bundles_type: bundles_type,
             current_params: params
           }
         } = socket
       ) do
    git_branch =
      cond do
        bundle_size_branch == "any" -> nil
        Bundles.has_bundles_in_project_default_branch?(project) -> project.default_branch
        true -> nil
      end

    bundle_type = string_to_bundle_type(bundles_type)

    %{period: {start_datetime, end_datetime}} =
      DatePicker.date_picker_params(params, "bundle-size")

    opts = [
      project_id: project.id,
      start_datetime: start_datetime,
      end_datetime: end_datetime,
      git_branch: git_branch,
      type: bundle_type
    ]

    bundle_size_analytics =
      case bundle_size_selected_widget do
        "download-size" ->
          project
          |> Bundles.bundle_download_size_analytics(opts)
          |> Enum.map(
            &[
              &1.date,
              &1.bundle_download_size
            ]
          )

        _ ->
          project
          |> Bundles.project_bundle_install_size_analytics(opts)
          |> Enum.map(
            &[
              &1.date,
              &1.bundle_install_size
            ]
          )
      end

    assign(socket, :bundle_size_analytics, bundle_size_analytics)
  end

  defp bundle_size_trend_label("last-7-days"), do: dgettext("dashboard_cache", "since last week")
  defp bundle_size_trend_label("last-12-months"), do: dgettext("dashboard_cache", "since last year")
  defp bundle_size_trend_label("custom"), do: dgettext("dashboard_cache", "since last period")
  defp bundle_size_trend_label(_), do: dgettext("dashboard_cache", "since last month")

  defp bundle_size_trend_value(last_bundle, previous_bundle) do
    if last_bundle && last_bundle.download_size && last_bundle.download_size > 0 &&
         previous_bundle && previous_bundle.download_size do
      (1 - previous_bundle.download_size / last_bundle.download_size) * 100
    else
      0.0
    end
  end

  def column_patch_sort(
        %{uri: uri, bundles_sort_by: bundles_sort_by, bundles_sort_order: bundles_sort_order} = _assigns,
        column_value
      ) do
    sort_order =
      case {bundles_sort_by == column_value, bundles_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "asc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("bundles-sort-by", column_value)
      |> Map.put("bundles-sort-order", sort_order)
      |> Query.clear_cursors()

    "?#{URI.encode_query(query_params)}"
  end

  def bundles_dropdown_item_patch_sort(bundles_sort_by, uri) do
    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("bundles-sort-by", bundles_sort_by)
      |> Query.clear_cursors()
      |> Map.delete("bundles-sort-order")

    "?#{URI.encode_query(query_params)}"
  end

  def sort_icon("desc") do
    "square_rounded_arrow_down"
  end

  def sort_icon("asc") do
    "square_rounded_arrow_up"
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      filter_id
      |> Filter.Operations.add_filter_to_query(socket)
      |> Query.clear_cursors()

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/bundles?#{updated_params}"
     )
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_query_params =
      params
      |> Filter.Operations.update_filters_in_query(socket)
      |> Query.clear_cursors()

    {:noreply,
     socket
     |> push_patch(
       to:
         ~p"/#{socket.assigns.selected_project.account.name}/#{socket.assigns.selected_project.name}/bundles?#{updated_query_params}"
     )
     # There's a DOM reconciliation bug where the dropdown closes and then reappears somewhere else on the page. To remedy, just nuke it entirely.
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event(
        "select_widget",
        %{"widget" => widget},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project, uri: uri}} = socket
      ) do
    socket =
      push_patch(
        socket,
        to:
          "/#{selected_account.name}/#{selected_project.name}/bundles?#{Query.put(uri.query, "bundle-size-selected-widget", widget)}",
        replace: true
      )

    {:noreply, socket}
  end

  def handle_event(
        "bundle_size_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: selected_account, selected_project: selected_project}} = socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("bundle-size-date-range", "custom")
        |> Query.put("bundle-size-start-date", start_date)
        |> Query.put("bundle-size-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "bundle-size-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{selected_account.name}/#{selected_project.name}/bundles?#{query_params}")}
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    ByteFormatter.format_bytes(bytes)
  end

  def format_bundle_type(:ipa), do: dgettext("dashboard_cache", "IPA")
  def format_bundle_type(:app), do: dgettext("dashboard_cache", "App bundle")
  def format_bundle_type(:xcarchive), do: dgettext("dashboard_cache", "XCArchive")
  def format_bundle_type(_), do: dgettext("dashboard_cache", "Unknown")

  def bundles_type_label("ipa"), do: dgettext("dashboard_cache", "IPA")
  def bundles_type_label("app"), do: dgettext("dashboard_cache", "App bundle")
  def bundles_type_label("xcarchive"), do: dgettext("dashboard_cache", "XCArchive")
  def bundles_type_label(_), do: dgettext("dashboard_cache", "Any")

  defp string_to_bundle_type("ipa"), do: :ipa
  defp string_to_bundle_type("app"), do: :app
  defp string_to_bundle_type("xcarchive"), do: :xcarchive
  defp string_to_bundle_type(_), do: nil

  def empty_state_light_background(assigns) do
    ~H"""
    <svg
      width="1184"
      height="1045"
      viewBox="0 0 1184 1045"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g opacity="0.6">
        <mask
          id="mask0_1277_52487"
          style="mask-type:alpha"
          maskUnits="userSpaceOnUse"
          x="0"
          y="0"
          width="1184"
          height="1045"
        >
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M672 817H336C334.343 817 333 818.343 333 820V898C333 899.657 334.343 901 336 901H672C673.657 901 675 899.657 675 898V820C675 818.343 673.657 817 672 817ZM336 816C333.791 816 332 817.791 332 820V898C332 900.209 333.791 902 336 902H672C674.209 902 676 900.209 676 898V820C676 817.791 674.209 816 672 816H336Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M329 817H4C2.34315 817 1 818.343 1 820V1041C1 1042.66 2.34314 1044 4 1044H329C330.657 1044 332 1042.66 332 1041V820C332 818.343 330.657 817 329 817ZM4 816C1.79086 816 0 817.791 0 820V1041C0 1043.21 1.79086 1045 4 1045H329C331.209 1045 333 1043.21 333 1041V820C333 817.791 331.209 816 329 816H4Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M490 902H336C334.343 902 333 903.343 333 905V1041C333 1042.66 334.343 1044 336 1044H490C491.657 1044 493 1042.66 493 1041V905C493 903.343 491.657 902 490 902ZM336 901C333.791 901 332 902.791 332 905V1041C332 1043.21 333.791 1045 336 1045H490C492.209 1045 494 1043.21 494 1041V905C494 902.791 492.209 901 490 901H336Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M995 902H497C495.343 902 494 903.343 494 905V1041C494 1042.66 495.343 1044 497 1044H995C996.657 1044 998 1042.66 998 1041V905C998 903.343 996.657 902 995 902ZM497 901C494.791 901 493 902.791 493 905V1041C493 1043.21 494.791 1045 497 1045H995C997.209 1045 999 1043.21 999 1041V905C999 902.791 997.209 901 995 901H497Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 902H1002C1000.34 902 999 903.343 999 905V1041C999 1042.66 1000.34 1044 1002 1044H1180C1181.66 1044 1183 1042.66 1183 1041V905C1183 903.343 1181.66 902 1180 902ZM1002 901C999.791 901 998 902.791 998 905V1041C998 1043.21 999.791 1045 1002 1045H1180C1182.21 1045 1184 1043.21 1184 1041V905C1184 902.791 1182.21 901 1180 901H1002Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M757 817H679C677.343 817 676 818.343 676 820V898C676 899.657 677.343 901 679 901H757C758.657 901 760 899.657 760 898V820C760 818.343 758.657 817 757 817ZM679 816C676.791 816 675 817.791 675 820V898C675 900.209 676.791 902 679 902H757C759.209 902 761 900.209 761 898V820C761 817.791 759.209 816 757 816H679Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M842 817H764C762.343 817 761 818.343 761 820V898C761 899.657 762.343 901 764 901H842C843.657 901 845 899.657 845 898V820C845 818.343 843.657 817 842 817ZM764 816C761.791 816 760 817.791 760 820V898C760 900.209 761.791 902 764 902H842C844.209 902 846 900.209 846 898V820C846 817.791 844.209 816 842 816H764Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 1H4C2.34315 1 1 2.34315 1 4V181C1 182.657 2.34315 184 4.00001 184H420C421.657 184 423 182.657 423 181V4C423 2.34315 421.657 1 420 1ZM4 0C1.79086 0 0 1.79087 0 4V181C0 183.209 1.79087 185 4.00001 185H420C422.209 185 424 183.209 424 181V4C424 1.79086 422.209 0 420 0H4Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M725 1H427C425.343 1 424 2.34314 424 4V181C424 182.657 425.343 184 427 184H725C726.657 184 728 182.657 728 181V4C728 2.34315 726.657 1 725 1ZM427 0C424.791 0 423 1.79086 423 4V181C423 183.209 424.791 185 427 185H725C727.209 185 729 183.209 729 181V4C729 1.79086 727.209 0 725 0H427Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M976 1H732C730.343 1 729 2.34314 729 4V181C729 182.657 730.343 184 732 184H976C977.657 184 979 182.657 979 181V4C979 2.34315 977.657 1 976 1ZM732 0C729.791 0 728 1.79086 728 4V181C728 183.209 729.791 185 732 185H976C978.209 185 980 183.209 980 181V4C980 1.79086 978.209 0 976 0H732Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 1H983C981.343 1 980 2.34315 980 4V96C980 97.6569 981.343 99 983 99H1180C1181.66 99 1183 97.6569 1183 96V4C1183 2.34314 1181.66 1 1180 1ZM983 0C980.791 0 979 1.79086 979 4V96C979 98.2091 980.791 100 983 100H1180C1182.21 100 1184 98.2091 1184 96V4C1184 1.79086 1182.21 0 1180 0H983Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 100H983C981.343 100 980 101.343 980 103V290C980 291.657 981.343 293 983 293H1180C1181.66 293 1183 291.657 1183 290V103C1183 101.343 1181.66 100 1180 100ZM983 99C980.791 99 979 100.791 979 103V290C979 292.209 980.791 294 983 294H1180C1182.21 294 1184 292.209 1184 290V103C1184 100.791 1182.21 99 1180 99H983Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M976 185H427C425.343 185 424 186.343 424 188V290C424 291.657 425.343 293 427 293H976C977.657 293 979 291.657 979 290V188C979 186.343 977.657 185 976 185ZM427 184C424.791 184 423 185.791 423 188V290C423 292.209 424.791 294 427 294H976C978.209 294 980 292.209 980 290V188C980 185.791 978.209 184 976 184H427Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 185H4.00001C2.34316 185 1 186.343 1 188V290C1 291.657 2.34315 293 4.00001 293H420C421.657 293 423 291.657 423 290V188C423 186.343 421.657 185 420 185ZM4.00001 184C1.79087 184 0 185.791 0 188V290C0 292.209 1.79087 294 4.00001 294H420C422.209 294 424 292.209 424 290V188C424 185.791 422.209 184 420 184H4.00001Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M36 294H4.00001C2.34315 294 1 295.343 1 297V400C1 401.657 2.34315 403 4 403H36C37.6569 403 39 401.657 39 400V297C39 295.343 37.6569 294 36 294ZM4.00001 293C1.79087 293 0 294.791 0 297V400C0 402.209 1.79086 404 4 404H36C38.2091 404 40 402.209 40 400V297C40 294.791 38.2091 293 36 293H4.00001Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M75 294H43C41.3431 294 40 295.343 40 297V400C40 401.657 41.3431 403 43 403H75C76.6569 403 78 401.657 78 400V297C78 295.343 76.6569 294 75 294ZM43 293C40.7909 293 39 294.791 39 297V400C39 402.209 40.7909 404 43 404H75C77.2091 404 79 402.209 79 400V297C79 294.791 77.2091 293 75 293H43Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M114 294H82C80.3431 294 79 295.343 79 297V400C79 401.657 80.3431 403 82 403H114C115.657 403 117 401.657 117 400V297C117 295.343 115.657 294 114 294ZM82 293C79.7909 293 78 294.791 78 297V400C78 402.209 79.7909 404 82 404H114C116.209 404 118 402.209 118 400V297C118 294.791 116.209 293 114 293H82Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M153 294H121C119.343 294 118 295.343 118 297V400C118 401.657 119.343 403 121 403H153C154.657 403 156 401.657 156 400V297C156 295.343 154.657 294 153 294ZM121 293C118.791 293 117 294.791 117 297V400C117 402.209 118.791 404 121 404H153C155.209 404 157 402.209 157 400V297C157 294.791 155.209 293 153 293H121Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 294H160C158.343 294 157 295.343 157 297V484C157 485.657 158.343 487 160 487H420C421.657 487 423 485.657 423 484V297C423 295.343 421.657 294 420 294ZM160 293C157.791 293 156 294.791 156 297V484C156 486.209 157.791 488 160 488H420C422.209 488 424 486.209 424 484V297C424 294.791 422.209 293 420 293H160Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 488H160C158.343 488 157 489.343 157 491V534C157 535.657 158.343 537 160 537H420C421.657 537 423 535.657 423 534V491C423 489.343 421.657 488 420 488ZM160 487C157.791 487 156 488.791 156 491V534C156 536.209 157.791 538 160 538H420C422.209 538 424 536.209 424 534V491C424 488.791 422.209 487 420 487H160Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M153 404H4C2.34315 404 1 405.343 1 407V534C1 535.657 2.34315 537 4 537H153C154.657 537 156 535.657 156 534V407C156 405.343 154.657 404 153 404ZM4 403C1.79086 403 0 404.791 0 407V534C0 536.209 1.79086 538 4 538H153C155.209 538 157 536.209 157 534V407C157 404.791 155.209 403 153 403H4Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 538H4C2.34315 538 1 539.343 1 541V728C1 729.657 2.34315 731 4.00001 731H420C421.657 731 423 729.657 423 728V541C423 539.343 421.657 538 420 538ZM4 537C1.79086 537 0 538.791 0 541V728C0 730.209 1.79087 732 4.00001 732H420C422.209 732 424 730.209 424 728V541C424 538.791 422.209 537 420 537H4Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 732H4.00001C2.34316 732 1 733.343 1 735V813C1 814.657 2.34314 816 4 816H420C421.657 816 423 814.657 423 813V735C423 733.343 421.657 732 420 732ZM4.00001 731C1.79087 731 0 732.791 0 735V813C0 815.209 1.79086 817 4 817H420C422.209 817 424 815.209 424 813V735C424 732.791 422.209 731 420 731H4.00001Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M624 623H427C425.343 623 424 624.343 424 626V813C424 814.657 425.343 816 427 816H624C625.657 816 627 814.657 627 813V626C627 624.343 625.657 623 624 623ZM427 622C424.791 622 423 623.791 423 626V813C423 815.209 424.791 817 427 817H624C626.209 817 628 815.209 628 813V626C628 623.791 626.209 622 624 622H427Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M940 623H631C629.343 623 628 624.343 628 626V813C628 814.657 629.343 816 631 816H940C941.657 816 943 814.657 943 813V626C943 624.343 941.657 623 940 623ZM631 622C628.791 622 627 623.791 627 626V813C627 815.209 628.791 817 631 817H940C942.209 817 944 815.209 944 813V626C944 623.791 942.209 622 940 622H631Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 623H947C945.343 623 944 624.343 944 626V813C944 814.657 945.343 816 947 816H1180C1181.66 816 1183 814.657 1183 813V626C1183 624.343 1181.66 623 1180 623ZM947 622C944.791 622 943 623.791 943 626V813C943 815.209 944.791 817 947 817H1180C1182.21 817 1184 815.209 1184 813V626C1184 623.791 1182.21 622 1180 622H947Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 817H849C847.343 817 846 818.343 846 820V898C846 899.657 847.343 901 849 901H1180C1181.66 901 1183 899.657 1183 898V820C1183 818.343 1181.66 817 1180 817ZM849 816C846.791 816 845 817.791 845 820V898C845 900.209 846.791 902 849 902H1180C1182.21 902 1184 900.209 1184 898V820C1184 817.791 1182.21 816 1180 816H849Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 294H427C425.343 294 424 295.343 424 297V619C424 620.657 425.343 622 427 622H1180C1181.66 622 1183 620.657 1183 619V297C1183 295.343 1181.66 294 1180 294ZM427 293C424.791 293 423 294.791 423 297V619C423 621.209 424.791 623 427 623H1180C1182.21 623 1184 621.209 1184 619V297C1184 294.791 1182.21 293 1180 293H427Z"
            fill="#C0C0C0"
          />
        </mask>
        <g mask="url(#mask0_1277_52487)">
          <rect width="1184" height="1045" fill="url(#paint0_radial_1277_52487)" fill-opacity="0.4" />
          <rect width="1184" height="1045" fill="url(#paint1_radial_1277_52487)" fill-opacity="0.4" />
          <rect width="1184" height="1045" fill="url(#paint2_radial_1277_52487)" fill-opacity="0.4" />
          <rect width="1184" height="1045" fill="url(#paint3_radial_1277_52487)" fill-opacity="0.4" />
        </g>
      </g>
      <defs>
        <radialGradient
          id="paint0_radial_1277_52487"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(883 292) rotate(-43.8958) scale(458.644 519.65)"
        >
          <stop stop-color="#E51C01" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint1_radial_1277_52487"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(411.5 627.5) rotate(134.109) scale(591.213 669.853)"
        >
          <stop stop-color="#FFC300" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint2_radial_1277_52487"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(725 628.5) rotate(39.3184) scale(557.109 631.212)"
        >
          <stop stop-color="#F44277" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint3_radial_1277_52487"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(339.5 441) rotate(-129.32) scale(535.79 607.057)"
        >
          <stop stop-color="#8366FF" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
      </defs>
    </svg>
    """
  end

  def empty_state_dark_background(assigns) do
    ~H"""
    <svg
      width="1184"
      height="1045"
      viewBox="0 0 1184 1045"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g opacity="0.6">
        <mask
          id="mask0_1277_52570"
          style="mask-type:alpha"
          maskUnits="userSpaceOnUse"
          x="0"
          y="0"
          width="1184"
          height="1045"
        >
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M672 817H336C334.343 817 333 818.343 333 820V898C333 899.657 334.343 901 336 901H672C673.657 901 675 899.657 675 898V820C675 818.343 673.657 817 672 817ZM336 816C333.791 816 332 817.791 332 820V898C332 900.209 333.791 902 336 902H672C674.209 902 676 900.209 676 898V820C676 817.791 674.209 816 672 816H336Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M329 817H4C2.34315 817 1 818.343 1 820V1041C1 1042.66 2.34314 1044 4 1044H329C330.657 1044 332 1042.66 332 1041V820C332 818.343 330.657 817 329 817ZM4 816C1.79086 816 0 817.791 0 820V1041C0 1043.21 1.79086 1045 4 1045H329C331.209 1045 333 1043.21 333 1041V820C333 817.791 331.209 816 329 816H4Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M490 902H336C334.343 902 333 903.343 333 905V1041C333 1042.66 334.343 1044 336 1044H490C491.657 1044 493 1042.66 493 1041V905C493 903.343 491.657 902 490 902ZM336 901C333.791 901 332 902.791 332 905V1041C332 1043.21 333.791 1045 336 1045H490C492.209 1045 494 1043.21 494 1041V905C494 902.791 492.209 901 490 901H336Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M995 902H497C495.343 902 494 903.343 494 905V1041C494 1042.66 495.343 1044 497 1044H995C996.657 1044 998 1042.66 998 1041V905C998 903.343 996.657 902 995 902ZM497 901C494.791 901 493 902.791 493 905V1041C493 1043.21 494.791 1045 497 1045H995C997.209 1045 999 1043.21 999 1041V905C999 902.791 997.209 901 995 901H497Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 902H1002C1000.34 902 999 903.343 999 905V1041C999 1042.66 1000.34 1044 1002 1044H1180C1181.66 1044 1183 1042.66 1183 1041V905C1183 903.343 1181.66 902 1180 902ZM1002 901C999.791 901 998 902.791 998 905V1041C998 1043.21 999.791 1045 1002 1045H1180C1182.21 1045 1184 1043.21 1184 1041V905C1184 902.791 1182.21 901 1180 901H1002Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M757 817H679C677.343 817 676 818.343 676 820V898C676 899.657 677.343 901 679 901H757C758.657 901 760 899.657 760 898V820C760 818.343 758.657 817 757 817ZM679 816C676.791 816 675 817.791 675 820V898C675 900.209 676.791 902 679 902H757C759.209 902 761 900.209 761 898V820C761 817.791 759.209 816 757 816H679Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M842 817H764C762.343 817 761 818.343 761 820V898C761 899.657 762.343 901 764 901H842C843.657 901 845 899.657 845 898V820C845 818.343 843.657 817 842 817ZM764 816C761.791 816 760 817.791 760 820V898C760 900.209 761.791 902 764 902H842C844.209 902 846 900.209 846 898V820C846 817.791 844.209 816 842 816H764Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 1H4C2.34315 1 1 2.34315 1 4V181C1 182.657 2.34315 184 4.00001 184H420C421.657 184 423 182.657 423 181V4C423 2.34315 421.657 1 420 1ZM4 0C1.79086 0 0 1.79087 0 4V181C0 183.209 1.79087 185 4.00001 185H420C422.209 185 424 183.209 424 181V4C424 1.79086 422.209 0 420 0H4Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M725 1H427C425.343 1 424 2.34314 424 4V181C424 182.657 425.343 184 427 184H725C726.657 184 728 182.657 728 181V4C728 2.34315 726.657 1 725 1ZM427 0C424.791 0 423 1.79086 423 4V181C423 183.209 424.791 185 427 185H725C727.209 185 729 183.209 729 181V4C729 1.79086 727.209 0 725 0H427Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M976 1H732C730.343 1 729 2.34314 729 4V181C729 182.657 730.343 184 732 184H976C977.657 184 979 182.657 979 181V4C979 2.34315 977.657 1 976 1ZM732 0C729.791 0 728 1.79086 728 4V181C728 183.209 729.791 185 732 185H976C978.209 185 980 183.209 980 181V4C980 1.79086 978.209 0 976 0H732Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 1H983C981.343 1 980 2.34315 980 4V96C980 97.6569 981.343 99 983 99H1180C1181.66 99 1183 97.6569 1183 96V4C1183 2.34314 1181.66 1 1180 1ZM983 0C980.791 0 979 1.79086 979 4V96C979 98.2091 980.791 100 983 100H1180C1182.21 100 1184 98.2091 1184 96V4C1184 1.79086 1182.21 0 1180 0H983Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 100H983C981.343 100 980 101.343 980 103V290C980 291.657 981.343 293 983 293H1180C1181.66 293 1183 291.657 1183 290V103C1183 101.343 1181.66 100 1180 100ZM983 99C980.791 99 979 100.791 979 103V290C979 292.209 980.791 294 983 294H1180C1182.21 294 1184 292.209 1184 290V103C1184 100.791 1182.21 99 1180 99H983Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M976 185H427C425.343 185 424 186.343 424 188V290C424 291.657 425.343 293 427 293H976C977.657 293 979 291.657 979 290V188C979 186.343 977.657 185 976 185ZM427 184C424.791 184 423 185.791 423 188V290C423 292.209 424.791 294 427 294H976C978.209 294 980 292.209 980 290V188C980 185.791 978.209 184 976 184H427Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 185H4.00001C2.34316 185 1 186.343 1 188V290C1 291.657 2.34315 293 4.00001 293H420C421.657 293 423 291.657 423 290V188C423 186.343 421.657 185 420 185ZM4.00001 184C1.79087 184 0 185.791 0 188V290C0 292.209 1.79087 294 4.00001 294H420C422.209 294 424 292.209 424 290V188C424 185.791 422.209 184 420 184H4.00001Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M36 294H4.00001C2.34315 294 1 295.343 1 297V400C1 401.657 2.34315 403 4 403H36C37.6569 403 39 401.657 39 400V297C39 295.343 37.6569 294 36 294ZM4.00001 293C1.79087 293 0 294.791 0 297V400C0 402.209 1.79086 404 4 404H36C38.2091 404 40 402.209 40 400V297C40 294.791 38.2091 293 36 293H4.00001Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M75 294H43C41.3431 294 40 295.343 40 297V400C40 401.657 41.3431 403 43 403H75C76.6569 403 78 401.657 78 400V297C78 295.343 76.6569 294 75 294ZM43 293C40.7909 293 39 294.791 39 297V400C39 402.209 40.7909 404 43 404H75C77.2091 404 79 402.209 79 400V297C79 294.791 77.2091 293 75 293H43Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M114 294H82C80.3431 294 79 295.343 79 297V400C79 401.657 80.3431 403 82 403H114C115.657 403 117 401.657 117 400V297C117 295.343 115.657 294 114 294ZM82 293C79.7909 293 78 294.791 78 297V400C78 402.209 79.7909 404 82 404H114C116.209 404 118 402.209 118 400V297C118 294.791 116.209 293 114 293H82Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M153 294H121C119.343 294 118 295.343 118 297V400C118 401.657 119.343 403 121 403H153C154.657 403 156 401.657 156 400V297C156 295.343 154.657 294 153 294ZM121 293C118.791 293 117 294.791 117 297V400C117 402.209 118.791 404 121 404H153C155.209 404 157 402.209 157 400V297C157 294.791 155.209 293 153 293H121Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 294H160C158.343 294 157 295.343 157 297V484C157 485.657 158.343 487 160 487H420C421.657 487 423 485.657 423 484V297C423 295.343 421.657 294 420 294ZM160 293C157.791 293 156 294.791 156 297V484C156 486.209 157.791 488 160 488H420C422.209 488 424 486.209 424 484V297C424 294.791 422.209 293 420 293H160Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 488H160C158.343 488 157 489.343 157 491V534C157 535.657 158.343 537 160 537H420C421.657 537 423 535.657 423 534V491C423 489.343 421.657 488 420 488ZM160 487C157.791 487 156 488.791 156 491V534C156 536.209 157.791 538 160 538H420C422.209 538 424 536.209 424 534V491C424 488.791 422.209 487 420 487H160Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M153 404H4C2.34315 404 1 405.343 1 407V534C1 535.657 2.34315 537 4 537H153C154.657 537 156 535.657 156 534V407C156 405.343 154.657 404 153 404ZM4 403C1.79086 403 0 404.791 0 407V534C0 536.209 1.79086 538 4 538H153C155.209 538 157 536.209 157 534V407C157 404.791 155.209 403 153 403H4Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 538H4C2.34315 538 1 539.343 1 541V728C1 729.657 2.34315 731 4.00001 731H420C421.657 731 423 729.657 423 728V541C423 539.343 421.657 538 420 538ZM4 537C1.79086 537 0 538.791 0 541V728C0 730.209 1.79087 732 4.00001 732H420C422.209 732 424 730.209 424 728V541C424 538.791 422.209 537 420 537H4Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M420 732H4.00001C2.34316 732 1 733.343 1 735V813C1 814.657 2.34314 816 4 816H420C421.657 816 423 814.657 423 813V735C423 733.343 421.657 732 420 732ZM4.00001 731C1.79087 731 0 732.791 0 735V813C0 815.209 1.79086 817 4 817H420C422.209 817 424 815.209 424 813V735C424 732.791 422.209 731 420 731H4.00001Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M624 623H427C425.343 623 424 624.343 424 626V813C424 814.657 425.343 816 427 816H624C625.657 816 627 814.657 627 813V626C627 624.343 625.657 623 624 623ZM427 622C424.791 622 423 623.791 423 626V813C423 815.209 424.791 817 427 817H624C626.209 817 628 815.209 628 813V626C628 623.791 626.209 622 624 622H427Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M940 623H631C629.343 623 628 624.343 628 626V813C628 814.657 629.343 816 631 816H940C941.657 816 943 814.657 943 813V626C943 624.343 941.657 623 940 623ZM631 622C628.791 622 627 623.791 627 626V813C627 815.209 628.791 817 631 817H940C942.209 817 944 815.209 944 813V626C944 623.791 942.209 622 940 622H631Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 623H947C945.343 623 944 624.343 944 626V813C944 814.657 945.343 816 947 816H1180C1181.66 816 1183 814.657 1183 813V626C1183 624.343 1181.66 623 1180 623ZM947 622C944.791 622 943 623.791 943 626V813C943 815.209 944.791 817 947 817H1180C1182.21 817 1184 815.209 1184 813V626C1184 623.791 1182.21 622 1180 622H947Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 817H849C847.343 817 846 818.343 846 820V898C846 899.657 847.343 901 849 901H1180C1181.66 901 1183 899.657 1183 898V820C1183 818.343 1181.66 817 1180 817ZM849 816C846.791 816 845 817.791 845 820V898C845 900.209 846.791 902 849 902H1180C1182.21 902 1184 900.209 1184 898V820C1184 817.791 1182.21 816 1180 816H849Z"
            fill="#C0C0C0"
          />
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M1180 294H427C425.343 294 424 295.343 424 297V619C424 620.657 425.343 622 427 622H1180C1181.66 622 1183 620.657 1183 619V297C1183 295.343 1181.66 294 1180 294ZM427 293C424.791 293 423 294.791 423 297V619C423 621.209 424.791 623 427 623H1180C1182.21 623 1184 621.209 1184 619V297C1184 294.791 1182.21 293 1180 293H427Z"
            fill="#C0C0C0"
          />
        </mask>
        <g mask="url(#mask0_1277_52570)">
          <rect width="1184" height="1045" fill="url(#paint0_radial_1277_52570)" fill-opacity="0.4" />
          <rect width="1184" height="1045" fill="url(#paint1_radial_1277_52570)" fill-opacity="0.4" />
          <rect width="1184" height="1045" fill="url(#paint2_radial_1277_52570)" fill-opacity="0.4" />
          <rect width="1184" height="1045" fill="url(#paint3_radial_1277_52570)" fill-opacity="0.4" />
        </g>
      </g>
      <defs>
        <radialGradient
          id="paint0_radial_1277_52570"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(883 292) rotate(-43.8958) scale(458.644 519.65)"
        >
          <stop stop-color="#E51C01" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint1_radial_1277_52570"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(411.5 627.5) rotate(134.109) scale(591.213 669.853)"
        >
          <stop stop-color="#FFC300" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint2_radial_1277_52570"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(725 628.5) rotate(39.3184) scale(557.109 631.212)"
        >
          <stop stop-color="#F44277" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint3_radial_1277_52570"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(339.5 441) rotate(-129.32) scale(535.79 607.057)"
        >
          <stop stop-color="#8366FF" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
      </defs>
    </svg>
    """
  end

  defp define_filters(_project) do
    platform_options = [
      :ios,
      :ios_simulator,
      :macos,
      :watchos,
      :watchos_simulator,
      :tvos,
      :tvos_simulator,
      :visionos,
      :visionos_simulator
    ]

    [
      %Filter.Filter{
        id: "name",
        field: :name,
        display_name: dgettext("dashboard_cache", "Name"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "git_branch",
        field: :git_branch,
        display_name: dgettext("dashboard_cache", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "type",
        field: :type,
        display_name: dgettext("dashboard_cache", "Type"),
        type: :option,
        options: [:app, :ipa, :xcarchive],
        options_display_names: %{
          app: dgettext("dashboard_cache", "App bundle"),
          ipa: dgettext("dashboard_cache", "IPA"),
          xcarchive: dgettext("dashboard_cache", "XCArchive")
        },
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "install_size",
        field: :install_size,
        display_name: dgettext("dashboard_cache", "Install size (MB)"),
        type: :number,
        operator: :>=,
        value: nil
      },
      %Filter.Filter{
        id: "download_size",
        field: :download_size,
        display_name: dgettext("dashboard_cache", "Download size (MB)"),
        type: :number,
        operator: :>=,
        value: nil
      },
      %Filter.Filter{
        id: "supported_platforms",
        field: :supported_platforms,
        display_name: dgettext("dashboard_cache", "Platform"),
        type: :option,
        options: platform_options,
        options_display_names: %{
          ios: "iOS",
          ios_simulator: "iOS Simulator",
          macos: "macOS",
          watchos: "watchOS",
          watchos_simulator: "watchOS Simulator",
          tvos: "tvOS",
          tvos_simulator: "tvOS Simulator",
          visionos: "visionOS",
          visionos_simulator: "visionOS Simulator"
        },
        operator: :==,
        value: nil
      }
    ]
  end
end
