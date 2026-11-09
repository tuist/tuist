# Read-only inventory of provisioned dashboard query contracts. This never
# contacts Grafana or reads secrets. Usage: mix run --no-start scripts/grafana_inventory.exs DIR

defmodule GrafanaInventory do
  def run(directory) do
    Path.wildcard(Path.join(directory, "*.json"))
    |> Enum.flat_map(fn path ->
      with {:ok, body} <- File.read(path), {:ok, dashboard} <- JSON.decode(body) do
        variables = datasource_variables(dashboard)
        collect(dashboard, Path.basename(path), variables, nil, "panel")
      else
        error -> raise "Cannot inventory #{path}: #{inspect(error)}"
      end
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1["source"], &1["datasource"], &1["expression"], JSON.encode!(&1)})
  end

  defp datasource_variables(map) when is_map(map) do
    own =
      case map do
        %{"kind" => "DatasourceVariable", "spec" => spec} -> %{spec["name"] => spec["pluginId"]}
        %{"type" => "datasource", "name" => name, "query" => type} -> %{name => type}
        _ -> %{}
      end

    Enum.reduce(Map.values(map), own, &Map.merge(&2, datasource_variables(&1)))
  end

  defp datasource_variables(list) when is_list(list),
    do: Enum.reduce(list, %{}, &Map.merge(&2, datasource_variables(&1)))

  defp datasource_variables(_), do: %{}

  defp collect(%{"kind" => "DataQuery"} = query, source, variables, inherited, context) do
    target(query["spec"], query["datasource"] || inherited, query["group"], source, variables, context)
  end

  defp collect(%{"kind" => "QueryVariable", "spec" => spec}, source, variables, inherited, _) do
    collect(spec["query"], source, variables, spec["datasource"] || inherited, "variable")
  end

  defp collect(%{"type" => "query", "query" => query} = variable, source, variables, inherited, _) do
    target = if is_binary(query), do: %{"query" => query}, else: query
    target(target, variable["datasource"] || inherited, nil, source, variables, "variable")
  end

  defp collect(map, source, variables, inherited, context) when is_map(map) do
    inherited = map["datasource"] || inherited
    context = if map["kind"] == "AnnotationQuery", do: "annotation", else: context

    own =
      Enum.flat_map(Map.get(map, "targets", []), fn query ->
        target(query, query["datasource"] || inherited, nil, source, variables, context)
      end)

    own ++
      Enum.flat_map(Map.delete(map, "targets"), fn {_key, value} ->
        collect(value, source, variables, inherited, context)
      end)
  end

  defp collect(list, source, variables, inherited, context) when is_list(list),
    do: Enum.flat_map(list, &collect(&1, source, variables, inherited, context))

  defp collect(_, _, _, _, _), do: []

  defp target(target, datasource, group, source, variables, context) when is_map(target) do
    reference = if is_map(datasource), do: datasource["uid"] || datasource["name"], else: datasource
    explicit_type = if is_map(datasource), do: datasource["type"]
    variable = if is_binary(reference), do: variables[String.replace(reference, ~r/^\$\{?([^}]+)\}?$/, "\\1")]
    type = explicit_type || variable || group || reference || "unknown"

    type = if target["queryType"] == "traceql", do: "tempo", else: type

    language =
      cond do
        type == "__expr__" -> "grafana-expression"
        is_binary(target["rawSql"]) -> "sql"
        type == "prometheus" -> "promql"
        type == "loki" -> "logql"
        type == "tempo" -> "traceql"
        true -> "unknown"
      end

    expression = target["rawSql"] || target["expr"] || target["query"] || target["expression"]

    if is_binary(expression) and String.trim(expression) != "" do
      modes = Map.take(target, ~w(instant range queryType qryType type format tableType exemplar direction))

      [
        Map.merge(modes, %{
          "source" => source,
          "datasource" => type,
          "datasource_reference" => reference,
          "language" => language,
          "context" => context,
          "expression" => expression,
          "query_type" => target["queryType"] || "default"
        })
      ]
    else
      []
    end
  end

  defp target(_, _, _, _, _, _), do: []
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
