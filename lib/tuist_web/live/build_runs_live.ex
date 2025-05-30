defmodule TuistWeb.BuildRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use TuistWeb.Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Projects
  alias Tuist.Runs

  def mount(_params, _session, %{assigns: %{selected_project: project}} = socket) do
    slug = Projects.get_project_slug_from_id(project.id)

    socket = assign(socket, :head_title, "#{gettext("Build Runs")} · #{slug} · Tuist")

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    uri = URI.new!("?" <> URI.encode_query(Map.take(params, ["build-runs-sort-by", "build-runs-sort-order"])))

    socket =
      socket
      |> assign(:uri, uri)
      |> assign_build_runs(params)

    {
      :noreply,
      socket
    }
  end

  defp assign_build_runs(%{assigns: %{selected_project: project}} = socket, params) do
    build_runs_sort_by = params["build-runs-sort-by"] || "ran-at"
    build_runs_sort_order = params["build-runs-sort-order"] || "desc"

    flop_filters = [
      %{field: :project_id, op: :==, value: project.id}
    ]

    order_by =
      case build_runs_sort_by do
        "duration" -> [:duration]
        _ -> [:inserted_at]
      end

    order_directions =
      case build_runs_sort_order do
        "asc" -> [:asc]
        _ -> [:desc]
      end

    options =
      build_runs_options_with_paging(
        %{filters: flop_filters, order_by: order_by, order_directions: order_directions},
        params
      )

    {build_runs, build_runs_meta} = Runs.list_build_runs(options, preload: :ran_by_account)

    socket
    |> assign(:build_runs, build_runs)
    |> assign(:build_runs_meta, build_runs_meta)
    |> assign(:build_runs_sort_by, build_runs_sort_by)
    |> assign(:build_runs_sort_order, build_runs_sort_order)
  end

  defp build_runs_options_with_paging(options, params) do
    cond do
      not is_nil(Map.get(params, "before")) ->
        options
        |> Map.put(:last, 20)
        |> Map.put(:before, Map.get(params, "before"))

      not is_nil(Map.get(params, "after")) ->
        options
        |> Map.put(:first, 20)
        |> Map.put(:after, Map.get(params, "after"))

      true ->
        Map.put(options, :first, 20)
    end
  end

  def sort_icon("desc") do
    "square_rounded_arrow_down"
  end

  def sort_icon("asc") do
    "square_rounded_arrow_up"
  end

  def column_patch_sort(
        %{uri: uri, build_runs_sort_by: build_runs_sort_by, build_runs_sort_order: build_runs_sort_order} = _assigns,
        column_value
      ) do
    sort_order =
      case {build_runs_sort_by == column_value, build_runs_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "desc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("build-runs-sort-by", column_value)
      |> Map.put("build-runs-sort-order", sort_order)
      |> Map.delete("after")
      |> Map.delete("before")

    "?#{URI.encode_query(query_params)}"
  end
end
