defmodule TuistWeb.GradleExecutionComponent do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  alias Tuist.Gradle
  alias Tuist.Gradle.ExecutionGraph
  alias Tuist.Utilities.DateFormatter

  @page_size 25

  def update(assigns, socket) do
    assigns = Map.update!(assigns, :params, &Map.filter(&1, fn {_key, value} -> is_binary(value) end))
    socket = cache_graph(socket, assigns.build)
    %{graph: graph, model: model, index: index} = socket.assigns.graph_cache
    selected = index[assigns.params["node"]] || index[List.first(model.node_ids)] || List.first(graph.nodes)
    search = assigns.params["graph-search"] || ""

    filtered =
      Enum.filter(
        socket.assigns.graph_cache.timeline,
        &String.contains?(String.downcase(&1.label), String.downcase(search))
      )

    timeline = paginate(filtered, assigns.params, "graph-page")
    selection_key = {assigns.build.id, selected && selected.id}

    socket =
      if socket.assigns[:selection_key] == selection_key do
        socket
      else
        {dependencies, dependents} = neighbors(selected, socket.assigns.graph_cache)

        assign(socket,
          selection_key: selection_key,
          task: selected_task(assigns.build.id, selected),
          neighbors: %{
            dependencies: dependencies,
            dependents: dependents,
            ordering: if(selected, do: ordering(selected, index), else: [])
          }
        )
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       graph: graph,
       model: model,
       selected: selected,
       search: search,
       chain: paginate(socket.assigns.graph_cache.chain, assigns.params, "chain-page"),
       rows: timeline.rows,
       page: timeline.page,
       page_count: timeline.page_count,
       start_at: socket.assigns.graph_cache.start_at,
       span: socket.assigns.graph_cache.span,
       dependencies: paginate(socket.assigns.neighbors.dependencies, assigns.params, "dependencies-page"),
       dependents: paginate(socket.assigns.neighbors.dependents, assigns.params, "dependents-page"),
       ordering: paginate(socket.assigns.neighbors.ordering, assigns.params, "ordering-page")
     )}
  end

  defp cache_graph(socket, build) do
    if socket.assigns[:graph_build_id] == build.id do
      socket
    else
      graph = ExecutionGraph.decode(build.execution_graph)
      model = ExecutionGraph.analyze(graph)
      index = Map.new(graph.nodes, &{&1.id, &1})
      {start_at, end_at} = time_range(graph.nodes)

      assign(socket,
        graph_build_id: build.id,
        graph_cache: %{
          graph: graph,
          model: model,
          index: index,
          successors: ExecutionGraph.successors(graph.nodes),
          chain: Enum.map(model.node_ids, &index[&1]),
          timeline: Enum.sort_by(graph.nodes, &{&1.started_at || "", &1.id}),
          start_at: start_at,
          span: max(end_at - start_at, 1)
        }
      )
    end
  end

  defp paginate(rows, params, key) do
    total = length(rows)
    page_count = max(ceil(total / @page_size), 1)

    page =
      case Integer.parse(params[key] || "1") do
        {number, ""} -> number |> max(1) |> min(page_count)
        _ -> 1
      end

    %{rows: Enum.slice(rows, (page - 1) * @page_size, @page_size), page: page, page_count: page_count, total: total}
  end

  defp time_range(nodes) do
    timed = Enum.filter(nodes, &(&1.started_at && &1.duration_ms))
    start_at = timed |> Enum.map(&timestamp(&1.started_at)) |> Enum.min(fn -> 0 end)
    end_at = timed |> Enum.map(&(timestamp(&1.started_at) + &1.duration_ms)) |> Enum.max(fn -> 1 end)
    {start_at, end_at}
  end

  defp neighbors(nil, _cache), do: {[], []}

  defp neighbors(selected, %{index: index, successors: successors}) do
    nodes = fn ids -> ids |> Enum.map(&index[&1]) |> Enum.reject(&is_nil/1) |> Enum.sort_by(&{&1.label, &1.id}) end
    {nodes.(selected.dependencies), nodes.(Map.get(successors, selected.id, []))}
  end

  defp selected_task(build_id, %{kind: "task"} = selected) do
    {tasks, _} =
      Gradle.list_tasks(build_id, %{
        filters: [
          %{field: :task_path, op: :==, value: selected.label},
          %{field: :build_path, op: :==, value: selected.build_path}
        ],
        page_size: 1
      })

    List.first(tasks)
  end

  defp selected_task(_build_id, _selected), do: nil

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: patch(socket.assigns, %{"graph-search" => search, "graph-page" => "1"}))}
  end

  defp patch(assigns, changes) do
    "/#{assigns.account.name}/#{assigns.project.name}/builds/build-runs/#{assigns.build.id}?" <>
      (assigns.params
       |> Map.drop(~w(account_handle project_handle build_run_id))
       |> Map.put("tab", "dependencies")
       |> then(fn params ->
         if Map.has_key?(changes, "node"),
           do: Map.drop(params, ~w(dependencies-page dependents-page ordering-page)),
           else: params
       end)
       |> Map.merge(changes)
       |> URI.encode_query())
  end

  attr :pagination, :map, required: true
  attr :param, :string, required: true
  attr :context, :map, required: true

  defp graph_pages(assigns) do
    ~H"""
    <div :if={@pagination.page_count > 1} class="graph-pages" data-pagination={@param}>
      <.button
        :if={@pagination.page > 1}
        label={dgettext("dashboard_gradle", "Previous")}
        variant="secondary"
        patch={patch(@context, %{@param => to_string(@pagination.page - 1)})}
      />
      <span>{dgettext("dashboard_gradle", "Page %{page} of %{count}",
        page: @pagination.page,
        count: @pagination.page_count
      )}</span>
      <.button
        :if={@pagination.page < @pagination.page_count}
        label={dgettext("dashboard_gradle", "Next")}
        variant="secondary"
        patch={patch(@context, %{@param => to_string(@pagination.page + 1)})}
      />
    </div>
    """
  end

  defp ordering(node, index) do
    [
      {:must_run_after, dgettext("dashboard_gradle", "Must run after")},
      {:should_run_after, dgettext("dashboard_gradle", "Should run after (soft)")},
      {:finalized_by, dgettext("dashboard_gradle", "Finalized by")}
    ]
    |> Enum.flat_map(fn {key, label} ->
      Enum.map(Map.get(node, key, []), &%{label: label, node: index[&1]})
    end)
    |> Enum.reject(&is_nil(&1.node))
  end

  defp timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} -> DateTime.to_unix(time, :millisecond)
      _ -> 0
    end
  end

  defp bar(node, start_at, span) do
    "margin-left: #{max(timestamp(node.started_at) - start_at, 0) / span * 100}%; width: #{node.duration_ms / span * 100}%;"
  end

  defp duration(nil), do: "—"
  defp duration(value), do: DateFormatter.format_duration_from_milliseconds(value)
end
