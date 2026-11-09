defmodule Pulse.Alerting.Rule do
  @moduledoc "Validated native threshold/recording rules and lossless, disabled Grafana definitions."
  alias Pulse.Alerting.Canonical
  alias Pulse.Alerting.Graph
  alias Pulse.Alerting.NativeExpression
  alias Pulse.Alerting.Principal
  alias Pulse.LogQL.AST.LogQuery
  alias Pulse.LogQL.QueryValidation
  alias Pulse.PromQL.Parser

  @native_fields ~w(kind name query threshold enabled cadence_ms for_ms keep_firing_ms no_data_policy labels notification_targets)
  @defaults %{
    "kind" => "promql_threshold",
    "enabled" => false,
    "cadence_ms" => 60_000,
    "for_ms" => 0,
    "keep_firing_ms" => 0,
    "no_data_policy" => "keep_last",
    "labels" => %{},
    "notification_targets" => []
  }

  def validate(%{"kind" => "grafana", "original" => original} = input) when is_map(original) do
    if Map.keys(input) -- ~w(kind original enabled) == [] and Map.get(input, "enabled", false) == false and
         is_binary(original["uid"]) and Graph.validate(original) == :ok and safe_json?(original, 0) and
         byte_size(Canonical.encode(input)) <= 262_144 do
      {:ok, Map.put(input, "enabled", false)}
    else
      {:error, :invalid_rule}
    end
  end

  def validate(%{"kind" => "promql_recording"} = input) do
    rule = Map.merge(Map.take(@defaults, ~w(enabled cadence_ms labels)), input)

    with true <- Map.keys(input) -- ~w(kind name query enabled cadence_ms labels) == [],
         true <- metric_name?(rule["name"]),
         true <- text?(rule["query"], 16_384),
         true <- is_boolean(rule["enabled"]),
         true <- duration?(rule["cadence_ms"], 1_000, 86_400_000),
         true <- labels?(rule["labels"]) and not Map.has_key?(rule["labels"], "__name__"),
         true <- Enum.all?(Map.keys(rule["labels"]), &label_name?/1),
         {:ok, _} <- Parser.parse(rule["query"]),
         true <- byte_size(Canonical.encode(rule)) <= 65_536 do
      {:ok, rule}
    else
      _ -> {:error, :invalid_rule}
    end
  end

  def validate(%{"kind" => "promql_recording_group"} = input) do
    rule = Map.merge(Map.take(@defaults, ~w(enabled cadence_ms)), input)

    with true <- Map.keys(input) -- ~w(kind name rules enabled cadence_ms) == [],
         true <- text?(rule["name"], 256),
         true <- is_boolean(rule["enabled"]),
         true <- duration?(rule["cadence_ms"], 1_000, 86_400_000),
         true <- is_list(rule["rules"]) and length(rule["rules"]) in 1..64,
         {:ok, rules} <- group_rules(rule["rules"]),
         rule = Map.put(rule, "rules", rules),
         true <- byte_size(Canonical.encode(rule)) <= 65_536 do
      {:ok, rule}
    else
      _ -> {:error, :invalid_rule}
    end
  end

  def validate(input) when is_map(input) do
    rule = Map.merge(@defaults, input)

    with true <- Map.keys(input) -- native_fields(rule["kind"]) == [],
         true <- rule["kind"] in ["promql_threshold", "logql_threshold", "expression_threshold"],
         true <- text?(rule["name"], 256),
         true <- is_boolean(rule["enabled"]),
         true <- target_ids?(rule["notification_targets"]),
         true <- duration?(rule["cadence_ms"], 1_000, 86_400_000),
         true <- duration?(rule["for_ms"], 0, 604_800_000),
         true <- duration?(rule["keep_firing_ms"], 0, 604_800_000),
         true <- rule["no_data_policy"] in ["keep_last", "ok"],
         true <- labels?(rule["labels"]) and not Enum.any?(["__name__", "alertname"], &Map.has_key?(rule["labels"], &1)),
         %{"op" => op, "value" => value} = threshold <- rule["threshold"],
         true <- op in ["gt", "lt", "eq"] and is_number(value) and map_size(threshold) == 2,
         :ok <- threshold_query(rule),
         true <- byte_size(Canonical.encode(rule)) <= 65_536 do
      {:ok, rule}
    else
      _ -> {:error, :invalid_rule}
    end
  end

  def validate(_), do: {:error, :invalid_rule}

  # Prometheus rule-file field names. Record names are unique within a group, so
  # each recorded series has exactly one producing rule.
  defp group_rules(rules) do
    rules = Enum.map(rules, &group_rule/1)
    names = Enum.map(rules, &(&1 && &1["record"]))

    if Enum.all?(rules) and length(Enum.uniq(names)) == length(names),
      do: {:ok, rules},
      else: {:error, :invalid_rule}
  end

  defp group_rule(%{} = item) do
    item = Map.merge(%{"labels" => %{}}, item)

    with true <- Map.keys(item) -- ~w(record expr labels) == [],
         true <- metric_name?(item["record"]) and text?(item["expr"], 16_384),
         true <- labels?(item["labels"]) and not Map.has_key?(item["labels"], "__name__"),
         true <- Enum.all?(Map.keys(item["labels"]), &label_name?/1),
         {:ok, _} <- Parser.parse(item["expr"]),
         do: item,
         else: (_ -> nil)
  end

  defp group_rule(_), do: nil

  defp native_fields("expression_threshold"), do: (@native_fields -- ["query"]) ++ ~w(sources expression)
  defp native_fields(_), do: @native_fields

  defp threshold_query(%{"kind" => "expression_threshold"} = rule), do: NativeExpression.validate(rule)

  defp threshold_query(%{"kind" => kind, "query" => query}) do
    if text?(query, 16_384), do: threshold_query(kind, query), else: {:error, :invalid_rule}
  end

  defp threshold_query(_), do: {:error, :invalid_rule}

  defp threshold_query("promql_threshold", query) do
    with {:ok, _} <- Parser.parse(query), do: :ok
  end

  defp threshold_query("logql_threshold", query) do
    with {:ok, ast} <- Pulse.LogQL.Parser.parse(query),
         false <- match?(%LogQuery{}, ast),
         do: QueryValidation.validate(ast)
  end

  def classification(%{"kind" => "grafana"}), do: ["alert:import"]

  def classification(%{"kind" => kind}) when kind in ["promql_recording", "promql_recording_group"],
    do: ["alert:record"]

  def classification(_), do: []

  def labels?(labels) when is_map(labels) do
    map_size(labels) <= 32 and
      Enum.all?(labels, fn {key, value} ->
        text?(key, 128) and
          is_binary(value) and byte_size(value) <= 512 and String.valid?(value)
      end)
  end

  def labels?(_), do: false

  def label_name?(name), do: text?(name, 128) and Regex.match?(~r/\A[a-zA-Z_][a-zA-Z0-9_]*\z/, name)
  defp metric_name?(name), do: text?(name, 256) and Regex.match?(~r/\A[a-zA-Z_:][a-zA-Z0-9_:]*\z/, name)

  defp target_ids?(ids) when is_list(ids),
    do: length(ids) <= 8 and length(Enum.uniq(ids)) == length(ids) and Enum.all?(ids, &Principal.valid_id?/1)

  defp target_ids?(_), do: false

  defp duration?(value, low, high), do: is_integer(value) and value >= low and value <= high
  defp text?(value, max), do: is_binary(value) and byte_size(value) in 1..max and String.valid?(value)

  # Import preserves unknown fields, but credential-bearing fields are not rule data.
  defp safe_json?(_, depth) when depth > 32, do: false

  defp safe_json?(map, depth) when is_map(map) do
    map_size(map) <= 1024 and
      Enum.all?(map, fn {key, value} ->
        is_binary(key) and String.downcase(key) not in ~w(password token secret authorization api_key securejsondata) and
          safe_json?(value, depth + 1)
      end)
  end

  defp safe_json?(list, depth) when is_list(list),
    do: length(list) <= 4096 and Enum.all?(list, &safe_json?(&1, depth + 1))

  defp safe_json?(value, _), do: is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)
end
