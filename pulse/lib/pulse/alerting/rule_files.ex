defmodule Pulse.Alerting.RuleFiles do
  @moduledoc """
  Converts the recording rules of a Prometheus rule file, or of a Grafana
  alert-rule export (provisioning format), into disabled native
  `promql_recording_group` rules. Preview only: nothing is written. Alerting
  rules and Grafana definitions that are not a single instant Prometheus
  query are reported as skipped, never silently reinterpreted.
  """
  alias Pulse.Alerting.Rule
  alias Pulse.PromQL.Parser

  @max_bytes 262_144
  @max_groups 64

  def preview(content) when is_binary(content) and byte_size(content) <= @max_bytes do
    with {:ok, document} <- decode(content),
         %{"groups" => groups} when is_list(groups) and length(groups) <= @max_groups <- document do
      groups
      |> Enum.reduce_while({:ok, [], []}, &convert_group/2)
      |> case do
        {:ok, rules, skipped} -> unique(Enum.reverse(rules), Enum.reverse(skipped))
        error -> error
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_import}
    end
  end

  def preview(_), do: {:error, :invalid_import}

  # YAML is untrusted: parse in a heap- and time-bounded process. JSON is YAML.
  defp decode(content) do
    task =
      Task.async(fn ->
        Process.flag(:max_heap_size, %{size: 8_000_000, kill: true, error_logger: false})

        try do
          case :yamerl_constr.string(content, [{:str_node_as_binary, true}, {:map_node_format, :map}]) do
            [document] -> {:ok, document}
            _ -> {:error, :invalid_import}
          end
        catch
          _, _ -> {:error, :invalid_import}
        end
      end)

    case Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :invalid_import}
    end
  end

  defp convert_group(%{"name" => name, "rules" => rules} = group, {:ok, acc, skipped})
       when is_binary(name) and is_list(rules) and length(rules) <= 1024 do
    grafana? = Enum.any?(rules, &(is_map(&1) and (is_map(&1["record"]) or Map.has_key?(&1, "data"))))
    {items, rule_skips} = if grafana?, do: grafana_rules(rules), else: prometheus_rules(group, rules)
    skipped = Enum.reverse(Enum.map(rule_skips, &Map.put(&1, "group", name)), skipped)

    case native_group(group, grafana?, items) do
      :empty -> {:cont, {:ok, acc, skipped}}
      {:ok, native} -> {:cont, {:ok, [%{"id" => slug(name), "rule" => native} | acc], skipped}}
      {:error, reason} -> {:cont, {:ok, acc, [%{"group" => name, "reason" => reason} | skipped]}}
    end
  end

  defp convert_group(_, _), do: {:halt, {:error, :invalid_import}}

  defp native_group(_group, _grafana?, []), do: :empty

  defp native_group(group, grafana?, items) do
    with {:ok, cadence} <- interval(Map.get(group, "interval")),
         :ok <- supported_group(group, grafana?) do
      native = %{
        "kind" => "promql_recording_group",
        "name" => group["name"],
        "enabled" => false,
        "cadence_ms" => cadence,
        "rules" => if(grafana?, do: order(items), else: items)
      }

      if match?({:ok, _}, Rule.validate(native)), do: {:ok, native}, else: {:error, "invalid_group"}
    end
  end

  # Prometheus 3 group fields. Group labels apply to every rule; rule labels win.
  defp supported_group(group, false) do
    cond do
      Map.keys(group) -- ~w(name interval query_offset limit labels rules) != [] -> {:error, "unsupported_group_field"}
      Map.get(group, "query_offset", "0s") not in ["0s", "0", 0] -> {:error, "query_offset_unsupported"}
      Map.get(group, "limit", 0) != 0 -> {:error, "limit_unsupported"}
      not is_map(Map.get(group, "labels", %{})) -> {:error, "invalid_group"}
      true -> :ok
    end
  end

  defp supported_group(_group, true), do: :ok

  defp prometheus_rules(group, rules) do
    group_labels = Map.get(group, "labels", %{})
    group_labels = if is_map(group_labels), do: group_labels, else: %{}

    Enum.reduce(rules, {[], []}, fn rule, {items, skipped} ->
      case prometheus_rule(rule, group_labels) do
        {:ok, item} -> {items ++ [item], skipped}
        {:skip, skip} -> {items, skipped ++ [skip]}
      end
    end)
  end

  defp prometheus_rule(%{"record" => record, "expr" => expr} = rule, group_labels) when is_binary(record) do
    labels = Map.get(rule, "labels") || %{}

    if Map.keys(rule) -- ~w(record expr labels) == [] and is_map(labels) do
      labels = group_labels |> Map.merge(labels) |> Map.new(fn {key, value} -> {key, text(value)} end)
      {:ok, %{"record" => record, "expr" => text(expr), "labels" => labels}}
    else
      {:skip, %{"rule" => record, "reason" => "unsupported_rule_field"}}
    end
  end

  defp prometheus_rule(%{"alert" => alert}, _),
    do: {:skip, %{"rule" => to_string(alert), "reason" => "alerting_rule_not_converted"}}

  defp prometheus_rule(_, _), do: {:skip, %{"reason" => "invalid_rule"}}

  # YAML scalars Prometheus reads into string fields.
  defp text(value) when is_binary(value), do: value
  defp text(value) when is_integer(value) or is_float(value) or is_boolean(value), do: to_string(value)
  defp text(_), do: nil

  # A Grafana recording rule records one instant Prometheus query by refId.
  defp grafana_rules(rules) do
    Enum.reduce(rules, {[], []}, fn rule, {items, skipped} ->
      title = if is_map(rule), do: rule["title"] || rule["uid"]

      case grafana_rule(rule) do
        {:ok, item} -> {items ++ [item], skipped}
        {:error, reason} -> {items, skipped ++ [%{"rule" => title, "reason" => reason}]}
      end
    end)
  end

  defp grafana_rule(%{"record" => %{"metric" => metric, "from" => from}, "data" => data} = rule)
       when is_binary(metric) and is_list(data) do
    with %{} = source <- Enum.find(data, &(is_map(&1) and &1["refId"] == from)),
         false <- source["datasourceUid"] == "__expr__",
         %{"expr" => expr} = model when is_binary(expr) <- source["model"],
         true <- Map.get(model, "instant", true) == true and Map.get(model, "range", false) == false,
         true <- Map.get(source["relativeTimeRange"] || %{}, "to", 0) == 0 do
      labels = rule["labels"] || %{}
      {:ok, %{"record" => metric, "expr" => expr, "labels" => if(is_map(labels), do: labels, else: %{})}}
    else
      true -> {:error, "expression_source_unsupported"}
      _ -> {:error, "not_an_instant_prometheus_query"}
    end
  end

  defp grafana_rule(%{"data" => _}), do: {:error, "alerting_rule_not_converted"}
  defp grafana_rule(_), do: {:error, "invalid_rule"}

  # Grafana evaluates a group's recordings independently. Order them so every
  # rule follows the rules it reads, which Prometheus-style ordered evaluation
  # needs to see same-tick results; independent rules keep their order.
  defp order(items) do
    names = MapSet.new(items, & &1["record"])

    deps =
      Map.new(items, fn item ->
        reads =
          case Parser.parse(item["expr"]) do
            {:ok, ast} -> ast |> metric_names([]) |> MapSet.new() |> MapSet.intersection(names)
            _ -> MapSet.new()
          end

        {item["record"], MapSet.delete(reads, item["record"])}
      end)

    sort(items, deps, MapSet.new(), [])
  end

  defp sort([], _deps, _done, acc), do: Enum.reverse(acc)

  defp sort(items, deps, done, acc) do
    ready = Enum.find(items, &MapSet.subset?(deps[&1["record"]], done)) || hd(items)
    sort(List.delete(items, ready), deps, MapSet.put(done, ready["record"]), [ready | acc])
  end

  defp metric_names({"__name__", :eq, name}, acc) when is_binary(name), do: [name | acc]
  defp metric_names(term, acc) when is_tuple(term), do: metric_names(Tuple.to_list(term), acc)
  defp metric_names(terms, acc) when is_list(terms), do: Enum.reduce(terms, acc, &metric_names/2)
  defp metric_names(term, acc) when is_map(term) and not is_struct(term), do: metric_names(Map.values(term), acc)
  defp metric_names(_, acc), do: acc

  # Prometheus durations (`1m`, `1h30m`) or Grafana integer seconds.
  defp interval(nil), do: {:ok, 60_000}
  defp interval(seconds) when is_integer(seconds), do: {:ok, seconds * 1000}

  defp interval(text) when is_binary(text) do
    parts = Regex.scan(~r/(\d+)(ms|s|m|h|d|w|y)/, text)
    units = %{"ms" => 1, "s" => 1000, "m" => 60_000, "h" => 3_600_000, "d" => 86_400_000, "w" => 604_800_000}

    if parts != [] and Enum.map_join(parts, &hd/1) == text and Enum.all?(parts, &Map.has_key?(units, List.last(&1))),
      do: {:ok, Enum.reduce(parts, 0, fn [_, n, unit], acc -> acc + String.to_integer(n) * units[unit] end)},
      else: {:error, "invalid_interval"}
  end

  defp interval(_), do: {:error, "invalid_interval"}

  defp slug(name) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9._-]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 128)

    if slug in ["", ".", ".."], do: "recording-group", else: slug
  end

  defp unique(rules, skipped) do
    ids = Enum.map(rules, & &1["id"])

    if length(Enum.uniq(ids)) == length(ids),
      do: {:ok, %{"rules" => rules, "skipped" => skipped}},
      else: {:error, :duplicate_rule_id}
  end
end
