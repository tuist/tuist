# Read-only inventory of provisioned dashboard query contracts. This never
# contacts Grafana or reads secrets. Usage: mix run --no-start scripts/grafana_inventory.exs DIR

defmodule GrafanaInventory do
  def run(directory) do
    Path.wildcard(Path.join(directory, "*.json"))
    |> Enum.flat_map(fn path ->
      with {:ok, body} <- File.read(path), {:ok, dashboard} <- JSON.decode(body) do
        collect(dashboard, Path.basename(path))
      else
        error -> raise "Cannot inventory #{path}: #{inspect(error)}"
      end
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1["source"], &1["datasource"], &1["expression"]})
  end

  defp collect(map, source) when is_map(map) do
    targets = Map.get(map, "targets", [])
    own = if is_list(targets), do: Enum.flat_map(targets, &target(&1, map["datasource"], source)), else: []
    own ++ Enum.flat_map(Map.values(map), &collect(&1, source))
  end

  defp collect(list, source) when is_list(list), do: Enum.flat_map(list, &collect(&1, source))
  defp collect(_, _), do: []

  defp target(target, inherited, source) when is_map(target) do
    datasource = Map.get(target, "datasource", inherited)
    type = if is_map(datasource), do: datasource["type"], else: datasource
    expression = target["expr"] || target["query"]

    if is_binary(expression) and expression != "" do
      [
        %{
          "source" => source,
          "datasource" => type || "unknown",
          "expression" => expression,
          "query_type" => target["queryType"] || "default"
        }
      ]
    else
      []
    end
  end

  defp target(_, _, _), do: []
end

case System.argv() do
  [directory] ->
    IO.puts(JSON.encode!(GrafanaInventory.run(directory)))

  [directory, destination] ->
    queries = GrafanaInventory.run(directory)
    File.mkdir_p!(Path.dirname(destination))
    File.write!(destination, JSON.encode!(queries) <> "\n")
    IO.puts("Wrote #{length(queries)} query contracts to #{destination}")

  _ ->
    raise "usage: mix run --no-start scripts/grafana_inventory.exs DASHBOARD_DIRECTORY"
end
