defmodule Pulse.Alerting.Graph do
  @moduledoc false

  def validate(%{"data" => nodes} = original) when is_list(nodes) and length(nodes) in 1..128 do
    refs = Enum.map(nodes, fn node -> if is_map(node), do: node["refId"] end)

    terminal =
      case original["record"] do
        %{"from" => ref} -> ref
        _ -> original["condition"]
      end

    with true <- Enum.all?(refs, &(is_binary(&1) and byte_size(&1) in 1..128)),
         true <- length(Enum.uniq(refs)) == length(refs) and terminal in refs,
         {:ok, graph} <- dependencies(nodes, refs),
         true <- consume(refs, graph, MapSet.new()) do
      :ok
    else
      _ -> {:error, :invalid_grafana_graph}
    end
  end

  def validate(_), do: {:error, :invalid_grafana_graph}

  defp dependencies(nodes, refs) do
    Enum.reduce_while(nodes, {:ok, %{}}, fn node, {:ok, graph} ->
      deps = node_dependencies(node)

      if Enum.all?(deps, &(&1 in refs)),
        do: {:cont, {:ok, Map.put(graph, node["refId"], deps)}},
        else: {:halt, {:error, :invalid_grafana_graph}}
    end)
  end

  defp node_dependencies(node) do
    if node["datasourceUid"] in ["__expr__", "-100"] or node["source_type"] == "expression",
      do: expression_dependencies(node["model"]),
      else: []
  end

  defp expression_dependencies(%{"type" => type, "expression" => expression})
       when type in ["threshold", "reduce"] and is_binary(expression), do: [expression]

  defp expression_dependencies(%{"type" => "math", "expression" => expression}) when is_binary(expression) do
    Regex.scan(~r/\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)/, expression)
    |> Enum.map(fn match -> match |> tl() |> Enum.find(&(&1 != "")) end)
  end

  defp expression_dependencies(_), do: [:unsupported]

  defp consume([], _graph, _visited), do: true

  defp consume(pending, graph, visited) do
    ready = Enum.filter(pending, fn ref -> Enum.all?(graph[ref], &MapSet.member?(visited, &1)) end)

    if ready == [],
      do: false,
      else: consume(pending -- ready, graph, Enum.reduce(ready, visited, &MapSet.put(&2, &1)))
  end
end
