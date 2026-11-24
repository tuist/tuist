defmodule Symptoms.Evidence.Roots do
  @moduledoc """
  Counts each failure once at its root (`symptoms/README.md` "Combining",
  step 5).

  - Edges are `{caller, callee}`. Strongly connected components collapse into
    one node: a single entity keeps its own name, a cycle becomes
    `{:cycle, sorted_members}`.
  - A degraded node is explained by a callee node degraded in the same
    direction whose start is no more than one window after its own. Roots
    are degraded nodes nobody explains; an explained node's root is found by
    following its explaining callees.
  - Shared cause: every caller (at least two) of a node degrades in the same
    direction with starts within one window, or `:min_unrelated` (default 3)
    unexplained roots in the same direction start within one window and
    share no callee. All members of a group, and every entity whose root is
    one of them, share the group's root key `{:shared_cause, resource}`
    (`resource` is `nil` for the no-shared-callee case, and the key is then
    `{:shared_cause, sorted_members}`).

  Degraded entries are maps `%{entity: term, direction: :up | :down, start:
  integer | DateTime}`; an integer start is a window index, a `DateTime` is
  converted with the `:window_seconds` option (default 60).
  """

  @type node_id :: term()
  @type direction :: :up | :down
  @type degraded :: %{entity: term(), direction: direction(), start: integer() | DateTime.t()}
  @type group :: %{
          key: term(),
          resource: node_id() | nil,
          direction: direction(),
          start: integer(),
          members: [node_id()]
        }
  @type result :: %{
          components: %{optional(term()) => node_id()},
          explained_by: %{optional(node_id()) => [node_id()]},
          roots: [node_id()],
          shared_cause: [group()],
          root_of: %{optional(term()) => term()}
        }

  @doc "Analyses degraded entities against caller→callee edges. See the module doc."
  @spec analyze([degraded()], [{term(), term()}], keyword()) :: result()
  def analyze(degraded, edges, opts \\ []) do
    window_seconds = Keyword.get(opts, :window_seconds, 60)
    degraded = Enum.map(degraded, &%{&1 | start: window_index(&1.start, window_seconds)})

    vertices = Enum.uniq(Enum.flat_map(edges, fn {a, b} -> [a, b] end) ++ Enum.map(degraded, & &1.entity))
    components = component_map(vertices, edges)
    callees = adjacency(edges, components, fn {a, b} -> {a, b} end)
    callers = adjacency(edges, components, fn {a, b} -> {b, a} end)

    # {node, direction} => earliest start among the node's degraded members.
    units =
      degraded
      |> Enum.group_by(&{components[&1.entity], &1.direction}, & &1.start)
      |> Map.new(fn {unit, starts} -> {unit, Enum.min(starts)} end)

    explainers = Map.new(units, fn {unit, start} -> {unit, explainers(unit, start, units, callees)} end)
    root_units = units |> Map.keys() |> Enum.filter(&(explainers[&1] == [])) |> Enum.sort()

    groups =
      resource_groups(units, callers) ++
        unrelated_groups(root_units, units, callees, Keyword.get(opts, :min_unrelated, 3))

    %{
      components: components,
      explained_by: explained_by(explainers),
      roots: root_units |> Enum.map(&elem(&1, 0)) |> Enum.uniq(),
      shared_cause: groups,
      root_of: Map.new(degraded, &{&1.entity, root_key(&1, components, units, explainers, groups)})
    }
  end

  defp window_index(%DateTime{} = at, window_seconds), do: div(DateTime.to_unix(at), window_seconds)
  defp window_index(index, _window_seconds) when is_integer(index), do: index

  defp component_map(vertices, edges) do
    graph = :digraph.new()

    try do
      Enum.each(vertices, &:digraph.add_vertex(graph, &1))
      Enum.each(edges, fn {a, b} -> :digraph.add_edge(graph, a, b) end)

      for component <- :digraph_utils.strong_components(graph),
          member <- component,
          into: %{},
          do: {member, node_id(component)}
    after
      :digraph.delete(graph)
    end
  end

  defp node_id([single]), do: single
  defp node_id(members), do: {:cycle, Enum.sort(members)}

  defp adjacency(edges, components, orient) do
    edges
    |> Enum.map(fn {a, b} -> orient.({components[a], components[b]}) end)
    |> Enum.reject(fn {from, to} -> from == to end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {node, neighbours} -> {node, MapSet.new(neighbours)} end)
  end

  defp explainers({node, direction}, start, units, callees) do
    callees
    |> Map.get(node, MapSet.new())
    |> Enum.filter(fn callee ->
      case Map.fetch(units, {callee, direction}) do
        {:ok, callee_start} -> callee_start <= start + 1
        :error -> false
      end
    end)
    |> Enum.sort()
    |> Enum.map(&{&1, direction})
  end

  defp explained_by(explainers) do
    explainers
    |> Enum.reject(fn {_unit, by} -> by == [] end)
    |> Enum.group_by(fn {{node, _direction}, _by} -> node end, fn {_unit, by} -> Enum.map(by, &elem(&1, 0)) end)
    |> Map.new(fn {node, lists} -> {node, lists |> List.flatten() |> Enum.uniq() |> Enum.sort()} end)
  end

  # Unexplained units reachable through explaining callees. The condensed
  # graph is acyclic, so this terminates.
  defp root_units(unit, explainers) do
    case explainers[unit] do
      [] -> [unit]
      by -> by |> Enum.flat_map(&root_units(&1, explainers)) |> Enum.uniq()
    end
  end

  defp resource_groups(units, callers) do
    for {resource, resource_callers} <- Enum.sort(callers),
        MapSet.size(resource_callers) >= 2,
        direction <- [:up, :down],
        starts = Enum.map(resource_callers, &Map.get(units, {&1, direction})),
        Enum.all?(starts),
        Enum.max(starts) - Enum.min(starts) <= 1 do
      degraded_resource = if Map.has_key?(units, {resource, direction}), do: [resource], else: []

      %{
        key: {:shared_cause, resource},
        resource: resource,
        direction: direction,
        start: Enum.min(starts),
        members: Enum.sort(Enum.to_list(resource_callers) ++ degraded_resource)
      }
    end
  end

  defp unrelated_groups(root_units, units, callees, min_size) do
    root_units
    |> Enum.group_by(&elem(&1, 1))
    |> Enum.sort()
    |> Enum.flat_map(fn {direction, direction_units} ->
      direction_units
      |> Enum.map(&{elem(&1, 0), units[&1]})
      |> Enum.sort_by(fn {node, start} -> {start, node} end)
      |> chunk_together()
      |> Enum.filter(&(length(&1) >= min_size and no_shared_callee?(&1, callees)))
      |> Enum.map(fn chunk ->
        members = chunk |> Enum.map(&elem(&1, 0)) |> Enum.sort()

        %{
          key: {:shared_cause, members},
          resource: nil,
          direction: direction,
          start: chunk |> Enum.map(&elem(&1, 1)) |> Enum.min(),
          members: members
        }
      end)
    end)
  end

  # Splits start-sorted `{node, start}` pairs into runs whose starts lie
  # within one window of the run's first start.
  defp chunk_together(pairs) do
    Enum.chunk_while(
      pairs,
      [],
      fn
        pair, [] -> {:cont, [pair]}
        {_, start} = pair, [{_, first} | _] = chunk when start <= first + 1 -> {:cont, chunk ++ [pair]}
        pair, chunk -> {:cont, chunk, [pair]}
      end,
      fn
        [] -> {:cont, []}
        chunk -> {:cont, chunk, []}
      end
    )
  end

  defp no_shared_callee?(chunk, callees) do
    chunk
    |> Enum.map(fn {node, _start} -> Map.get(callees, node, MapSet.new()) end)
    |> Enum.reduce(&MapSet.intersection/2)
    |> Enum.empty?()
  end

  defp root_key(entry, components, units, explainers, groups) do
    unit = {components[entry.entity], entry.direction}

    {root, _direction} =
      unit
      |> root_units(explainers)
      |> Enum.min_by(fn {node, _direction} = root -> {units[root], node} end)

    case Enum.find(groups, &(root in &1.members)) do
      nil -> root
      group -> group.key
    end
  end
end
