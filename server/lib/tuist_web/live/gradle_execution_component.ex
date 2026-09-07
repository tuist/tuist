defmodule TuistWeb.GradleExecutionComponent do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  alias Tuist.Gradle
  alias Tuist.Gradle.ExecutionGraph
  alias Tuist.Utilities.DateFormatter

  def update(assigns, socket) do
    graph = ExecutionGraph.decode(assigns.build.execution_graph)
    model = ExecutionGraph.analyze(graph)
    index = Map.new(graph.nodes, &{&1.id, &1})
    selected = index[assigns.params["node"]] || index[List.first(model.node_ids)] || List.first(graph.nodes)
    search = assigns.params["graph-search"] || ""
    filtered = Enum.filter(graph.nodes, &String.contains?(String.downcase(&1.label), String.downcase(search)))

    page_count = max(ceil(length(filtered) / 25), 1)
    page = min(page_number(assigns.params), page_count)
    {start_at, end_at} = time_range(graph.nodes)
    {dependencies, dependents} = neighbors(selected, index, graph.nodes)
    task = selected_task(assigns.build.id, selected)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       graph: graph,
       model: model,
       selected: selected,
       task: task,
       search: search,
       chain: Enum.map(model.node_ids, &index[&1]),
       rows: filtered |> Enum.sort_by(&{&1.started_at || "", &1.id}) |> Enum.slice((page - 1) * 25, 25),
       page: page,
       page_count: page_count,
       start_at: start_at,
       span: max(end_at - start_at, 1),
       dependencies: dependencies,
       dependents: dependents,
       ordering: if(selected, do: ordering(selected, index), else: [])
     )}
  end

  defp page_number(params) do
    case Integer.parse(params["graph-page"] || "1") do
      {number, ""} -> max(number, 1)
      _ -> 1
    end
  end

  defp time_range(nodes) do
    timed = Enum.filter(nodes, &(&1.started_at && &1.duration_ms))
    start_at = timed |> Enum.map(&timestamp(&1.started_at)) |> Enum.min(fn -> 0 end)
    end_at = timed |> Enum.map(&(timestamp(&1.started_at) + &1.duration_ms)) |> Enum.max(fn -> 1 end)
    {start_at, end_at}
  end

  defp neighbors(nil, _index, _nodes), do: {[], []}

  defp neighbors(selected, index, nodes) do
    {selected.dependencies |> Enum.map(&index[&1]) |> Enum.reject(&is_nil/1),
     Enum.filter(nodes, &(selected.id in &1.dependencies))}
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
       |> Map.merge(changes)
       |> URI.encode_query())
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
