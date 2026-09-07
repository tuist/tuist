defmodule Tuist.Gradle.ExecutionGraph do
  @moduledoc """
  Analysis of the execution graph captured for one Gradle invocation.

  Dependency reachability expresses potential impact. The longest chain uses
  observed node durations and hard ordering constraints, not worker scheduling.
  Missing timings, missing dependencies and cycles make the model unavailable.
  """

  def analyze(%{nodes: nodes, status: status}) when status == "complete" and nodes != [] do
    index = Map.new(nodes, &{&1.id, &1})
    predecessors = Map.new(nodes, &{&1.id, Enum.uniq(&1.dependencies ++ Map.get(&1, :must_run_after, []))})

    predecessors =
      Enum.reduce(nodes, predecessors, fn node, acc ->
        Enum.reduce(Map.get(node, :finalized_by, []), acc, fn finalizer, result ->
          Map.update(result, finalizer, [node.id], &Enum.uniq([node.id | &1]))
        end)
      end)

    complete? =
      map_size(index) == length(nodes) and
        Enum.all?(nodes, &(is_integer(Map.get(&1, :duration_ms)) and &1.duration_ms >= 0)) and
        Enum.all?(predecessors, fn {id, deps} -> Map.has_key?(index, id) and Enum.all?(deps, &Map.has_key?(index, &1)) end)

    if complete? do
      successors = reverse(predecessors)
      counts = Map.new(predecessors, fn {id, deps} -> {id, length(deps)} end)
      ready = counts |> Enum.filter(fn {_id, count} -> count == 0 end) |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      distances = walk(:queue.from_list(ready), counts, successors, predecessors, index, %{})

      if map_size(distances) == map_size(index) do
        {last, {duration, _}} = Enum.max_by(distances, fn {id, {duration, _}} -> {duration, id} end)
        %{status: "available", duration_ms: duration, node_ids: path(last, distances, [])}
      else
        unavailable()
      end
    else
      unavailable()
    end
  end

  def analyze(_), do: unavailable()

  def validate(nil), do: :ok

  def validate(%{nodes: nodes}) when is_list(nodes) do
    edges =
      Enum.sum_by(nodes, fn node ->
        Enum.sum_by([:dependencies, :must_run_after, :should_run_after, :finalized_by], &length(Map.get(node, &1, [])))
      end)

    ids = MapSet.new(nodes, & &1.id)

    if length(nodes) <= 20_000 and edges <= 100_000 and MapSet.size(ids) == length(nodes),
      do: :ok,
      else: {:error, :invalid_execution_graph}
  end

  def validate(_), do: {:error, :invalid_execution_graph}

  def successors(nodes), do: nodes |> Map.new(&{&1.id, &1.dependencies}) |> reverse()

  def decode(value) when value in [nil, ""], do: %{status: "unavailable", nodes: []}

  def decode(value) do
    # Only these known keys are accepted; never intern client-controlled keys.
    graph = JSON.decode!(value)

    %{
      status: graph["status"],
      nodes:
        Enum.map(graph["nodes"] || [], fn node ->
          %{
            id: node["id"],
            kind: node["kind"],
            build_path: node["build_path"],
            project_path: node["project_path"],
            label: node["label"],
            dependencies: node["dependencies"] || [],
            must_run_after: node["must_run_after"] || [],
            should_run_after: node["should_run_after"] || [],
            finalized_by: node["finalized_by"] || [],
            duration_ms: node["duration_ms"],
            started_at: node["started_at"]
          }
        end)
    }
  end

  defp unavailable, do: %{status: "unavailable", duration_ms: nil, node_ids: []}

  defp reverse(predecessors) do
    Enum.reduce(predecessors, %{}, fn {id, deps}, acc ->
      Enum.reduce(deps, acc, &Map.update(&2, &1, [id], fn ids -> [id | ids] end))
    end)
  end

  defp walk(queue, counts, successors, predecessors, index, distances) do
    case :queue.out(queue) do
      {:empty, _} ->
        distances

      {{:value, id}, queue} ->
        {duration, parent} =
          predecessors
          |> Map.fetch!(id)
          |> Enum.map(fn dep -> {elem(Map.fetch!(distances, dep), 0), dep} end)
          |> Enum.max(fn -> {0, nil} end)

        distances = Map.put(distances, id, {duration + index[id].duration_ms, parent})

        {queue, counts} =
          Enum.reduce(Map.get(successors, id, []), {queue, counts}, fn child, {queue, counts} ->
            counts = Map.update!(counts, child, &(&1 - 1))
            {if(counts[child] == 0, do: :queue.in(child, queue), else: queue), counts}
          end)

        walk(queue, counts, successors, predecessors, index, distances)
    end
  end

  defp path(nil, _distances, result), do: result
  defp path(id, distances, result), do: path(elem(distances[id], 1), distances, [id | result])
end
