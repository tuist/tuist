defmodule TuistWeb.GenerateRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use TuistWeb.Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.RanByBadge

  alias Tuist.CommandEvents
  alias Tuist.Projects

  def mount(_params, _session, %{assigns: %{selected_project: project}} = socket) do
    slug = Projects.get_project_slug_from_id(project.id)

    {:ok, assign(socket, :head_title, "#{gettext("Generate Runs")} · #{slug} · Tuist")}
  end

  def handle_params(params, _uri, %{assigns: %{selected_project: _project}} = socket) do
    uri = URI.new!("?" <> URI.encode_query(Map.take(params, ["generate_runs_sort_by", "generate_runs_sort_order"])))

    generate_runs_sort_by = params["generate_runs_sort_by"] || "ran_at"
    generate_runs_sort_order = params["generate_runs_sort_order"] || "desc"

    {
      :noreply,
      socket
      |> assign(
        :uri,
        uri
      )
      |> assign(
        :generate_runs_sort_by,
        generate_runs_sort_by
      )
      |> assign(
        :generate_runs_sort_order,
        generate_runs_sort_order
      )
      |> assign_generate_runs(params)
    }
  end

  def assign_generate_runs(
        %{
          assigns: %{
            selected_project: project,
            generate_runs_sort_by: generate_runs_sort_by,
            generate_runs_sort_order: generate_runs_sort_order
          }
        } = socket,
        params
      ) do
    order_by = String.to_atom(generate_runs_sort_by)
    order_direction = String.to_atom(generate_runs_sort_order)

    {generate_runs, generate_runs_meta} =
      list_generate_runs(project.id, params, order_by, order_direction)

    socket
    |> assign(:generate_runs, generate_runs)
    |> assign(:generate_runs_meta, generate_runs_meta)
  end

  defp list_generate_runs(project_id, %{"after" => after_cursor}, order_by, order_direction) do
    list_generate_runs(project_id,
      after: after_cursor,
      order_by: order_by,
      order_direction: order_direction
    )
  end

  defp list_generate_runs(project_id, %{"before" => before}, order_by, order_direction) do
    list_generate_runs(project_id,
      before: before,
      order_by: order_by,
      order_direction: order_direction
    )
  end

  defp list_generate_runs(project_id, _params, order_by, order_direction) do
    list_generate_runs(project_id,
      order_by: order_by,
      order_direction: order_direction
    )
  end

  defp list_generate_runs(project_id, attrs) do
    options = %{
      filters: [
        %{field: :project_id, op: :==, value: project_id},
        %{field: :name, op: :in, value: ["generate"]}
      ],
      order_by: [Keyword.get(attrs, :order_by, :created_at)],
      order_directions: [Keyword.get(attrs, :order_direction, :desc)]
    }

    options =
      cond do
        not is_nil(Keyword.get(attrs, :before)) ->
          options
          |> Map.put(:last, 20)
          |> Map.put(:before, Keyword.get(attrs, :before))

        not is_nil(Keyword.get(attrs, :after)) ->
          options
          |> Map.put(:first, 20)
          |> Map.put(:after, Keyword.get(attrs, :after))

        true ->
          Map.put(options, :first, 20)
      end

    CommandEvents.list_command_events(options)
  end

  def sort_icon("desc") do
    "square_rounded_arrow_down"
  end

  def sort_icon("asc") do
    "square_rounded_arrow_up"
  end

  def column_patch_sort(
        %{uri: uri, generate_runs_sort_by: generate_runs_sort_by, generate_runs_sort_order: generate_runs_sort_order} =
          _assigns,
        column_value
      ) do
    sort_order =
      case {generate_runs_sort_by == column_value, generate_runs_sort_order} do
        {true, "asc"} -> "desc"
        {true, _} -> "asc"
        {false, _} -> "asc"
      end

    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("generate_runs_sort_by", column_value)
      |> Map.put("generate_runs_sort_order", sort_order)
      |> Map.delete("after")
      |> Map.delete("before")

    "?#{URI.encode_query(query_params)}"
  end

  def generate_runs_dropdown_item_patch_sort(generate_runs_sort_by, uri) do
    query_params =
      uri.query
      |> URI.decode_query()
      |> Map.put("generate_runs_sort_by", generate_runs_sort_by)
      |> Map.delete("after")
      |> Map.delete("before")
      |> Map.delete("generate_runs_sort_order")

    "?#{URI.encode_query(query_params)}"
  end
end
