defmodule TuistWeb.BundleLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Bundles.UploadedByBadgeCell
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.TrendBadge
  import TuistWeb.Previews.PlatformIcon

  alias Tuist.Bundles
  alias Tuist.Projects
  alias Tuist.Utilities.ByteFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @table_page_size 20

  def mount(%{"bundle_id" => bundle_id}, _session, %{assigns: %{selected_project: selected_project}} = socket) do
    bundle = get_selected_bundle(bundle_id)

    all_artifacts = flatten_artifacts(bundle.artifacts)

    artifacts_by_id =
      Enum.reduce(all_artifacts, %{}, fn artifact, acc ->
        if not is_nil(artifact.id) do
          Map.put(acc, artifact.id, artifact)
        end
      end)

    artifacts_by_path =
      Enum.reduce(all_artifacts, %{}, fn artifact, acc ->
        Map.put(acc, artifact.path, artifact)
      end)

    base_path =
      if Enum.empty?(all_artifacts) do
        bundle.name <> ".app"
      else
        hd(all_artifacts).path |> String.split("/") |> hd()
      end

    artifacts_by_path =
      Map.put(artifacts_by_path, base_path, bundle)

    socket =
      socket
      |> assign(:bundle, bundle)
      |> assign(:duplicates, find_duplicates(bundle.artifacts))
      |> assign(
        :head_title,
        "#{bundle.name} · #{dgettext("dashboard_cache", "Bundle")} · #{Projects.get_project_slug_from_id(selected_project.id)} · Tuist"
      )
      |> assign(:all_artifacts, all_artifacts)
      |> assign(:artifacts_by_id, artifacts_by_id)
      |> assign(:artifacts_by_path, artifacts_by_path)
      |> assign(:base_path, base_path)

    {:ok, socket}
  end

  def handle_params(
        params,
        _url,
        %{assigns: %{bundle: bundle, duplicates: duplicates, selected_project: selected_project, base_path: base_path}} =
          socket
      ) do
    bundle_size_analysis_page_params =
      params
      |> Enum.filter(fn {key, _value} -> String.starts_with?(key, "bundle-size-analysis-table-page-") end)
      |> Enum.map(fn {key, _value} -> key end)

    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(
              params,
              [
                "filter",
                "file-breakdown-sort-by",
                "file-breakdown-filter",
                "file-breakdown-page",
                "tab",
                "current-path"
              ] ++ bundle_size_analysis_page_params
            )
          )
      )

    filter = params["filter"] || ""

    series = to_chart_series(bundle, filter, duplicates)

    table_artifact = build_root_table_artifact(bundle, base_path, duplicates)

    selected_artifact =
      case params["current-path"] do
        nil ->
          table_artifact

        current_path ->
          case Map.get(socket.assigns.artifacts_by_path, current_path) do
            nil -> table_artifact
            artifact -> build_artifact_for_table(artifact, duplicates)
          end
      end

    socket =
      socket
      |> assign(series: series)
      |> assign(filter: filter)
      |> assign(uri: uri)
      |> assign(:selected_tab, params["tab"] || "overview")
      |> assign_module_breakdown(params)
      |> assign_file_breakdown(params)
      |> assign(:install_size_deviation, Bundles.install_size_deviation(bundle))
      |> assign(
        :last_bundle,
        Bundles.last_project_bundle(selected_project, git_branch: selected_project.default_branch, bundle: bundle)
      )
      |> assign_table_artifact(selected_artifact, params)
      |> assign(:bundle_size_analysis_sunburst_chart_selected_artifact, selected_artifact)

    {:noreply, socket}
  end

  defp assign_file_breakdown(%{assigns: %{all_artifacts: all_artifacts}} = socket, params) do
    file_breakdown_filter = params["file-breakdown-filter"] || ""
    file_breakdown_sort_by = params["file-breakdown-sort-by"] || "size"
    file_breakdown_sort_order = params["file-breakdown-sort-order"] || "desc"
    file_breakdown_page = String.to_integer(params["file-breakdown-page"] || "1")

    file_breakdown_filtered_artifacts =
      Enum.filter(all_artifacts, fn artifact ->
        String.contains?(String.downcase(artifact.path), String.downcase(file_breakdown_filter)) &&
          Enum.empty?(artifact.children)
      end)

    file_breakdown_page_count =
      max(div(length(file_breakdown_filtered_artifacts), @table_page_size), 1)

    file_breakdown_current_page_artifacts =
      file_breakdown_filtered_artifacts
      |> sort_file_breakdown_artifacts(
        file_breakdown_sort_by,
        file_breakdown_sort_order
      )
      |> Enum.slice(
        (file_breakdown_page - 1) * @table_page_size,
        @table_page_size
      )

    socket
    |> assign(:file_breakdown_filter, file_breakdown_filter)
    |> assign(:file_breakdown_page, file_breakdown_page)
    |> assign(:file_breakdown_page_count, file_breakdown_page_count)
    |> assign(
      :file_breakdown_current_page_artifacts,
      file_breakdown_current_page_artifacts
    )
    |> assign(:file_breakdown_sort_by, file_breakdown_sort_by)
    |> assign(:file_breakdown_sort_order, file_breakdown_sort_order)
  end

  defp assign_module_breakdown(%{assigns: %{all_artifacts: all_artifacts}} = socket, params) do
    module_breakdown_filter = params["module-breakdown-filter"] || ""
    module_breakdown_sort_by = params["module-breakdown-sort-by"] || "size"
    module_breakdown_sort_order = params["module-breakdown-sort-order"] || "desc"
    module_breakdown_page = String.to_integer(params["module-breakdown-page"] || "1")

    module_breakdown_filtered_artifacts =
      all_artifacts
      |> Enum.filter(&String.ends_with?(&1.path, ".framework"))
      |> Enum.map(
        &Map.put(
          &1,
          :name,
          &1.path |> String.split("/") |> List.last() |> String.split(".") |> List.first()
        )
      )
      |> Enum.filter(&String.contains?(String.downcase(&1.name), String.downcase(module_breakdown_filter)))

    module_breakdown_page_count =
      max(div(length(module_breakdown_filtered_artifacts), @table_page_size), 1)

    module_breakdown_current_page_artifacts =
      module_breakdown_filtered_artifacts
      |> sort_module_breakdown_artifacts(
        module_breakdown_sort_by,
        module_breakdown_sort_order
      )
      |> Enum.slice(
        (module_breakdown_page - 1) * @table_page_size,
        @table_page_size
      )

    socket
    |> assign(:module_breakdown_filter, module_breakdown_filter)
    |> assign(:module_breakdown_page, module_breakdown_page)
    |> assign(:module_breakdown_page_count, module_breakdown_page_count)
    |> assign(
      :module_breakdown_current_page_artifacts,
      module_breakdown_current_page_artifacts
    )
    |> assign(:module_breakdown_sort_by, module_breakdown_sort_by)
    |> assign(:module_breakdown_sort_order, module_breakdown_sort_order)
  end

  def handle_event(
        "filter",
        %{"value" => filter},
        %{assigns: %{selected_project: selected_project, bundle: bundle, uri: uri}} = socket
      ) do
    {:noreply,
     push_patch(socket,
       to:
         "/#{selected_project.account.name}/#{selected_project.name}/bundles/#{bundle.id}?#{Query.put(uri.query, "filter", filter)}"
     )}
  end

  def handle_event("search-file-breakdown", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/bundles/#{socket.assigns.bundle.id}?#{socket.assigns.uri.query |> Query.put("file-breakdown-filter", search) |> Query.drop("file-breakdown-page")}"
      )

    {:noreply, socket}
  end

  def handle_event("search-module-breakdown", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/bundles/#{socket.assigns.bundle.id}?#{socket.assigns.uri.query |> Query.put("module-breakdown-filter", search) |> Query.drop("module-breakdown-page")}"
      )

    {:noreply, socket}
  end

  def handle_event(
        "update-bundle-size-analysis-sunburst-chart-table-selected-artifact",
        %{
          "artifact" =>
            %{
              "name" => name,
              "value" => value,
              "artifact_id" => artifact_id,
              "path" => path,
              "artifact_type" => artifact_type
            } = artifact
        } = params,
        %{assigns: %{selected_project: selected_project, bundle: bundle}} = socket
      ) do
    children =
      Enum.map(
        artifact["children"] || [],
        &%{
          name: &1["name"],
          value: &1["value"],
          artifact_type: &1["artifact_type"],
          artifact_id: &1["artifact_id"],
          path: &1["path"],
          duplicate?: &1["duplicate?"]
        }
      )

    artifact = %{
      name: name,
      path: path,
      value: value,
      artifact_id: artifact_id,
      artifact_type: artifact_type,
      children: children
    }

    cleaned_params = remove_pagination_params(params)

    socket =
      socket
      |> assign(:bundle_size_analysis_sunburst_chart_selected_artifact, artifact)
      |> assign_table_artifact(artifact, cleaned_params)
      |> push_patch(
        to:
          "/#{selected_project.account.name}/#{selected_project.name}/bundles/#{bundle.id}?#{Query.put(socket.assigns.uri.query, "current-path", path)}"
      )

    {:noreply, socket}
  end

  def handle_event(
        "update-bundle-size-analysis-sunburst-chart-table-selected-root",
        params,
        %{assigns: %{bundle: bundle, base_path: base_path, duplicates: duplicates, selected_project: selected_project}} =
          socket
      ) do
    table_artifact =
      bundle
      |> build_root_table_artifact(base_path, duplicates)
      |> Map.put(:id, bundle.id)
      |> Map.put(:artifact_id, nil)

    cleaned_params = remove_pagination_params(params)

    socket =
      socket
      |> assign(
        :bundle_size_analysis_sunburst_chart_selected_artifact,
        table_artifact
      )
      |> assign_table_artifact(table_artifact, cleaned_params)
      |> push_patch(
        to:
          "/#{selected_project.account.name}/#{selected_project.name}/bundles/#{bundle.id}?#{Query.drop(socket.assigns.uri.query, "current-path")}"
      )

    {:noreply, socket}
  end

  def handle_event(
        "update-bundle-size-analysis-sunburst-chart-table-selected-parent",
        params,
        %{
          assigns: %{
            bundle: bundle,
            bundle_size_analysis_sunburst_chart_selected_artifact: bundle_size_analysis_sunburst_chart_selected_artifact,
            artifacts_by_id: artifacts_by_id,
            base_path: base_path,
            duplicates: duplicates
          }
        } = socket
      ) do
    artifact =
      Map.get(artifacts_by_id, bundle_size_analysis_sunburst_chart_selected_artifact.artifact_id)

    table_artifact =
      if is_nil(artifact) do
        bundle
        |> build_root_table_artifact(base_path, duplicates)
        |> Map.put(:id, bundle.id)
        |> Map.put(:artifact_id, nil)
        |> Map.put(:artifact_type, :directory)
      else
        build_artifact_for_table(artifact, duplicates)
      end

    cleaned_params = remove_pagination_params(params)

    socket =
      socket
      |> assign_table_artifact(table_artifact, cleaned_params)
      |> assign(
        :bundle_size_analysis_sunburst_chart_selected_artifact,
        table_artifact
      )

    {:noreply, socket}
  end

  def handle_event(
        "update-bundle-size-analysis-sunburst-chart-table-highlighted-parent",
        _params,
        %{
          assigns: %{
            bundle: bundle,
            bundle_size_analysis_sunburst_chart_selected_artifact: bundle_size_analysis_sunburst_chart_selected_artifact,
            artifacts_by_id: artifacts_by_id
          }
        } = socket
      ) do
    artifact =
      Map.get(artifacts_by_id, bundle_size_analysis_sunburst_chart_selected_artifact.artifact_id)

    table_artifact =
      if is_nil(artifact) do
        %{
          name: bundle.name,
          value: bundle.install_size,
          id: bundle.id,
          artifact_id: nil
        }
      else
        %{
          name: artifact.path |> String.split("/") |> List.last(),
          value: artifact.size,
          id: artifact.id,
          artifact_id: artifact.id
        }
      end

    socket =
      assign(
        socket,
        :bundle_size_analysis_sunburst_chart_table_artifact,
        table_artifact
      )

    {:noreply, socket}
  end

  def handle_event(
        "update-bundle-size-analysis-sunburst-chart-table-highlighted-artifact",
        %{"artifact" => %{"name" => name, "value" => value, "artifact_id" => artifact_id} = artifact} = params,
        socket
      ) do
    children =
      Enum.map(
        artifact["children"] || [],
        &%{
          name: &1["name"],
          value: &1["value"],
          artifact_type: &1["artifact_type"],
          artifact_id: &1["artifact_id"],
          path: &1["path"],
          duplicate?: &1["duplicate?"]
        }
      )

    artifact = %{name: name, value: value, artifact_id: artifact_id, children: children}

    cleaned_params = remove_pagination_params(params)

    socket = assign_table_artifact(socket, artifact, cleaned_params)

    {:noreply, socket}
  end

  def handle_event(
        "update-bundle-size-analysis-sunburst-chart-table-no-highlighted-artifact",
        params,
        %{assigns: %{bundle_size_analysis_sunburst_chart_selected_artifact: artifact}} = socket
      ) do
    cleaned_params = remove_pagination_params(params)

    socket = assign_table_artifact(socket, artifact, cleaned_params)

    {:noreply, socket}
  end

  def handle_event("delete_bundle", _params, %{assigns: %{bundle: bundle, selected_project: selected_project}} = socket) do
    Bundles.delete_bundle!(bundle)

    {
      :noreply,
      push_navigate(socket, to: ~p"/#{selected_project.account.name}/#{selected_project.name}/bundles")
    }
  end

  def sort_icon("desc") do
    "square_rounded_arrow_down"
  end

  def sort_icon("asc") do
    "square_rounded_arrow_up"
  end

  defp sort_file_breakdown_artifacts(artifacts, "path", "asc") do
    Enum.sort_by(artifacts, & &1.path, :desc)
  end

  defp sort_file_breakdown_artifacts(artifacts, "path", "desc") do
    Enum.sort_by(artifacts, & &1.path, :asc)
  end

  defp sort_file_breakdown_artifacts(artifacts, "size", "asc") do
    Enum.sort_by(artifacts, & &1.size)
  end

  defp sort_file_breakdown_artifacts(artifacts, "size", "desc") do
    Enum.sort_by(artifacts, & &1.size, :desc)
  end

  defp sort_file_breakdown_artifacts(artifacts, _, _), do: artifacts

  defp sort_module_breakdown_artifacts(artifacts, "name", "asc") do
    Enum.sort_by(artifacts, & &1.name, :desc)
  end

  defp sort_module_breakdown_artifacts(artifacts, "name", "desc") do
    Enum.sort_by(artifacts, & &1.name, :asc)
  end

  defp sort_module_breakdown_artifacts(artifacts, "size", "asc") do
    Enum.sort_by(artifacts, & &1.size)
  end

  defp sort_module_breakdown_artifacts(artifacts, "size", "desc") do
    Enum.sort_by(artifacts, & &1.size, :desc)
  end

  defp sort_module_breakdown_artifacts(artifacts, _, _), do: artifacts

  defp find_duplicates(artifacts) do
    all_artifacts = flatten_artifacts(artifacts)

    all_artifacts
    |> Enum.group_by(& &1.shasum)
    |> Enum.filter(fn {_shasum, artifacts} -> length(artifacts) > 1 end)
    |> MapSet.new(fn {shasum, artifacts} ->
      %{
        shasum: shasum,
        artifacts: artifacts,
        size: Enum.reduce(artifacts, 0, fn duplicate, acc -> acc + duplicate.size end)
      }
    end)
    |> Enum.sort_by(& &1.size)
    |> Enum.reverse()
  end

  defp flatten_artifacts(artifacts) do
    Enum.reduce(artifacts, [], fn artifact, acc ->
      [artifact | acc] ++ flatten_artifacts(artifact.children || [])
    end)
  end

  def file_breakdown_column_patch_sort(
        %{uri: uri, file_breakdown_sort_by: file_breakdown_sort_by, file_breakdown_sort_order: file_breakdown_sort_order} =
          _assigns,
        column_value
      ) do
    sort_order =
      case {file_breakdown_sort_by == column_value, file_breakdown_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "asc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("file-breakdown-sort-by", column_value)
      |> Map.put("file-breakdown-sort-order", sort_order)
      |> Map.delete("file-breakdown-page")

    "?#{URI.encode_query(query_params)}"
  end

  def module_breakdown_column_patch_sort(
        %{
          uri: uri,
          module_breakdown_sort_by: module_breakdown_sort_by,
          module_breakdown_sort_order: module_breakdown_sort_order
        } = _assigns,
        column_value
      ) do
    sort_order =
      case {module_breakdown_sort_by == column_value, module_breakdown_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "asc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("module-breakdown-sort-by", column_value)
      |> Map.put("module-breakdown-sort-order", sort_order)
      |> Map.delete("module-breakdown-page")

    "?#{URI.encode_query(query_params)}"
  end

  def file_breakdown_dropdown_item_patch_sort(file_breakdown_sort_by, uri) do
    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("file-breakdown-sort-by", file_breakdown_sort_by)
      |> Map.delete("file-breakdown-page")
      |> Map.delete("file-breakdown-sort-order")

    "?#{URI.encode_query(query_params)}"
  end

  def module_breakdown_dropdown_item_patch_sort(module_breakdown_sort_by, uri) do
    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("module-breakdown-sort-by", module_breakdown_sort_by)
      |> Map.delete("module-breakdown-page")
      |> Map.delete("module-breakdown-sort-order")

    "?#{URI.encode_query(query_params)}"
  end

  def to_chart_series(bundle, filter, duplicates) do
    %{
      data: build_tree_data(bundle.artifacts, filter, duplicates),
      radius: [60, "90%"],
      type: "sunburst",
      emphasis: %{
        focus: "ancestor"
      },
      levels: [
        %{},
        %{
          itemStyle: %{
            opacity: 1.0
          }
        },
        %{
          itemStyle: %{
            opacity: 0.8
          }
        },
        %{
          itemStyle: %{
            opacity: 0.6
          }
        },
        %{
          itemStyle: %{
            opacity: 0.4
          }
        }
      ],
      highlightPolicy: "ancestor",
      visibleMin: 500,
      label: %{
        show: false
      },
      itemStyle: %{
        borderWidth: 1,
        borderColor: "var:noora-surface-background-primary",
        opacity: 1
      }
    }
  end

  def build_tree_data(artifacts, filter, duplicates) do
    artifacts
    |> Enum.filter(fn artifact ->
      is_nil(artifact.artifact_id)
    end)
    |> Enum.map(fn artifact ->
      {node, matches} = artifact_to_node_with_match(artifact, filter, duplicates)
      if matches, do: node
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp artifact_to_node_with_match(artifact, filter, duplicates) do
    colors = %{
      :binary => "var:noora-sunburst-binaries",
      :localization => "var:noora-sunburst-localizations",
      :font => "var:noora-sunburst-fonts",
      :asset => "var:noora-sunburst-assets",
      :video => "var:noora-sunburst-videos",
      :duplicate => "var:noora-sunburst-duplicates",
      :unknown => "var:noora-sunburst-unknown",
      :directory => "var:noora-sunburst-directory",
      :file => "var:noora-sunburst-files"
    }

    self_matches = artifact.path |> String.downcase() |> String.contains?(String.downcase(filter))
    duplicate_shasums = MapSet.new(duplicates, & &1.shasum)

    # Check if this artifact is a duplicate
    duplicate? = artifact.shasum && MapSet.member?(duplicate_shasums, artifact.shasum)
    effective_type = if duplicate?, do: :duplicate, else: to_atom(artifact.artifact_type)

    base = %{
      id: artifact.id,
      artifact_id: artifact.artifact_id,
      value: artifact.size,
      name: Path.basename(artifact.path),
      path: artifact.path,
      artifact_type: artifact.artifact_type,
      duplicate?: duplicate?,
      itemStyle: %{
        color: Map.get(colors, effective_type) || colors[:umapped]
      }
    }

    case artifact.children do
      [] ->
        {base, self_matches}

      [single_child] ->
        map_single_child(single_child, filter, duplicates, self_matches, base)

      children ->
        children_with_matches =
          children
          |> filter_collapsed_children()
          |> Enum.map(fn child ->
            artifact_to_node_with_match(child, filter, duplicates)
          end)

        matching_children =
          children_with_matches
          |> Enum.filter(fn {_, matches} -> matches end)
          |> Enum.map(fn {node, _} -> node end)

        any_child_matches = matching_children != []

        if self_matches || any_child_matches do
          {Map.put(base, :children, matching_children), true}
        else
          {base, false}
        end
    end
  end

  defp filter_collapsed_children(children) do
    Enum.filter(children, &(not &1.collapsed? or is_nil(&1.collapsed?)))
  end

  defp map_single_child(single_child, filter, duplicates, self_matches, base) do
    {child_node, child_matches} =
      artifact_to_node_with_match(single_child, filter, duplicates)

    if self_matches || child_matches do
      node = %{
        id: child_node.id,
        artifact_id: child_node.artifact_id,
        value: child_node.value,
        artifact_type: child_node.artifact_type,
        duplicate?: child_node[:duplicate?] || false,
        name: "#{base.name}/#{child_node.name}",
        path: "#{base.path}/#{child_node.path}",
        children: child_node[:children] || [],
        itemStyle: child_node.itemStyle
      }

      {node, true}
    else
      {base, false}
    end
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    ByteFormatter.format_bytes(bytes)
  end

  defp to_atom(input) when is_binary(input), do: String.to_existing_atom(input)
  defp to_atom(input) when is_atom(input), do: input

  defp get_selected_bundle(bundle_id) do
    case Bundles.get_bundle(bundle_id, preload: :uploaded_by_account) do
      {:error, :not_found} ->
        raise NotFoundError, dgettext("dashboard_cache", "Bundle not found.")

      {:ok, bundle} ->
        bundle
    end
  end

  attr :platform, :atom, required: true

  def platform_label(assigns) do
    ~H"""
    <div data-part="label">
      <.icon name={platform_icon_name(@platform)} />
      <span>{Tuist.AppBuilds.platform_string(@platform)}</span>
    </div>
    """
  end

  def space_usage(artifact, bundle) do
    space_usage =
      artifact.size / bundle.install_size * 100

    if space_usage < 0.1 do
      dgettext("dashboard_cache", "< 0.1 %")
    else
      dgettext("dashboard_cache", "%{space_usage} %",
        space_usage:
          space_usage
          |> Decimal.from_float()
          |> Decimal.round(1)
      )
    end
  end

  defp assign_table_artifact(socket, artifact, params) do
    artifact_path = Map.get(artifact, :path, "unknown")
    path_hash = :md5 |> :crypto.hash(artifact_path) |> Base.encode16() |> String.slice(0, 8)
    page_param = "bundle-size-analysis-table-page-#{path_hash}"

    bundle_size_analysis_sunburst_chart_table_page =
      String.to_integer(params[page_param] || "1")

    table_page_size = 5

    artifact_children =
      Enum.map(
        artifact.children,
        &add_collapsed_to_artifact(&1, socket)
      )

    current_page_children =
      Enum.slice(
        artifact_children,
        (bundle_size_analysis_sunburst_chart_table_page - 1) * table_page_size,
        table_page_size
      )

    bundle_size_analysis_sunburst_chart_table_page_count =
      max(div(length(artifact_children), table_page_size), 1)

    socket
    |> assign(:bundle_size_analysis_sunburst_chart_table_artifact, artifact)
    |> assign(
      :bundle_size_analysis_sunburst_chart_table_page,
      bundle_size_analysis_sunburst_chart_table_page
    )
    |> assign(
      :bundle_size_analysis_sunburst_chart_table_page_count,
      bundle_size_analysis_sunburst_chart_table_page_count
    )
    |> assign(
      :bundle_size_analysis_sunburst_chart_table_current_page_artifacts,
      current_page_children
    )
    |> assign(
      :bundle_size_analysis_sunburst_chart_table_page_param,
      page_param
    )
  end

  defp add_collapsed_to_artifact(artifact, %{assigns: %{artifacts_by_path: artifacts_by_path}} = _socket) do
    path = Map.get(artifact, :path)
    full_artifact = path && Map.get(artifacts_by_path, path)

    if full_artifact do
      collapsed = Map.get(full_artifact, :collapsed?, false)
      Map.put(artifact, :collapsed?, collapsed)
    else
      artifact
    end
  end

  defp remove_pagination_params(params) do
    params
    |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "bundle-size-analysis-table-page-") end)
    |> Map.new()
  end

  defp build_artifact_for_table(artifact, duplicates) do
    duplicate_shasums = MapSet.new(duplicates, & &1.shasum)

    %{
      path: artifact.path,
      name: artifact.path |> String.split("/") |> List.last(),
      value: artifact.size,
      id: artifact.id,
      artifact_id: artifact.artifact_id,
      artifact_type: artifact.artifact_type || :directory,
      children: build_artifact_children(artifact.children || [], duplicate_shasums)
    }
  end

  defp build_root_table_artifact(bundle, base_path, duplicates) do
    duplicate_shasums = MapSet.new(duplicates, & &1.shasum)

    %{
      path: base_path,
      name: bundle.name,
      value: bundle.install_size,
      artifact_type: :directory,
      children: build_artifact_children(bundle.artifacts, duplicate_shasums)
    }
  end

  defp build_artifact_children(artifacts, duplicate_shasums) do
    artifacts
    |> Enum.map(
      &%{
        value: &1.size,
        name: &1.path |> String.split("/") |> List.last(),
        artifact_type: &1.artifact_type,
        artifact_id: &1.artifact_id,
        path: &1.path,
        duplicate?: &1.shasum && MapSet.member?(duplicate_shasums, &1.shasum)
      }
    )
    |> Enum.sort_by(& &1.value, :desc)
  end

  def format_bundle_type(:ipa), do: dgettext("dashboard_cache", "IPA")
  def format_bundle_type(:app), do: dgettext("dashboard_cache", "App bundle")
  def format_bundle_type(:xcarchive), do: dgettext("dashboard_cache", "XCArchive")
  def format_bundle_type(_), do: dgettext("dashboard_cache", "Unknown")
end
