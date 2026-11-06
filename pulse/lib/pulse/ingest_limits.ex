defmodule Pulse.IngestLimits do
  @moduledoc """
  Per-request ingest budgets, shared by the JSON and native receivers.

  Limits apply to supplied records and attribute entries, including malformed
  records and duplicate keys, before decoding can drop or collapse them. An
  over-budget request is rejected in full; nothing is appended to storage.
  """

  alias Pulse.Runtime

  @defaults %{
    max_records: 10_000,
    max_attributes: 128,
    max_key_bytes: 256,
    max_value_bytes: 16_384,
    max_attribute_bytes: 65_536,
    max_depth: 16,
    max_nodes: 1_024,
    max_trace_nodes: 262_144,
    max_otlp_nodes: 262_144
  }

  def config do
    overrides = Runtime.get_env(:pulse, __MODULE__, [])

    Map.new(@defaults, fn {key, default} ->
      value = Keyword.get(overrides, key, default)

      if !(is_integer(value) and value in 1..2_147_483_647) do
        raise ArgumentError, "#{inspect(__MODULE__)} #{key} must be an integer in 1..2147483647"
      end

      {key, value}
    end)
  end

  def native_options do
    limits = config()

    {limits.max_records, limits.max_attributes, limits.max_key_bytes, limits.max_value_bytes,
     limits.max_attribute_bytes}
  end

  @doc "Validate a parsed JSON request before expanding it into records."
  def validate(:sentry, payload) do
    limits = %{config() | max_value_bytes: 1_048_576, max_attribute_bytes: 1_048_576}
    payload |> walk(limits, 0, {0, 0}) |> finish()
  end

  def validate(protocol, payload) when protocol in [:otlp, :otlp_traces, :otlp_metrics, :loki] do
    limits = config()

    case protocol do
      :otlp -> validate_otlp(payload, limits)
      :otlp_traces -> validate_traces(payload, limits)
      :otlp_metrics -> validate_metrics(payload, limits)
      :loki -> validate_loki(payload, limits)
    end
  end

  defp validate_loki(payload, limits) do
    field(payload, "streams")
    |> reduce_list({0, 0}, &loki_stream(&1, limits, &2))
    |> finish()
  end

  defp loki_stream(stream, limits, {records, groups}) do
    with :ok <- group_limit(groups + 1, limits),
         :ok <- attributes(field(stream, "stream"), limits, false) do
      reduce_list(field(stream, "values"), {records, groups + 1}, &loki_record(&1, limits, &2))
    end
  end

  defp loki_record(value, limits, {count, groups}) do
    with :ok <- record_limit(count + 1, limits),
         :ok <- loki_metadata(value, limits) do
      {:ok, {count + 1, groups}}
    end
  end

  defp loki_metadata([_, _, metadata], limits), do: attributes(metadata, limits, false)
  defp loki_metadata(_, _), do: :ok

  defp validate_otlp(payload, limits) do
    # Typed kvlists add several JSON levels per logical AnyValue level. Keep
    # the normalized envelope below the native JSON reader's fixed ceiling.
    limits = %{limits | max_depth: min(limits.max_depth, 32)}

    with :ok <- otlp_nodes(payload, limits.max_otlp_nodes) do
      field(payload, "resourceLogs")
      |> reduce_list({0, 0}, &otlp_resource(&1, limits, &2))
      |> finish()
    end
  end

  defp otlp_resource(resource, limits, {records, groups}) do
    with :ok <- otlp_group_limit(groups + 1, limits),
         :ok <- attributes(field(field(resource, "resource"), "attributes"), limits, true) do
      reduce_list(field(resource, "scopeLogs"), {records, groups + 1}, &otlp_scope(&1, limits, &2))
    end
  end

  defp otlp_scope(scope, limits, {count, groups}) do
    with :ok <- otlp_group_limit(groups + 1, limits),
         :ok <- attributes(field(field(scope, "scope"), "attributes"), limits, true) do
      reduce_list(field(scope, "logRecords"), {count, groups + 1}, &otlp_record(&1, limits, &2))
    end
  end

  defp otlp_record(record, limits, {count, groups}) do
    with :ok <- record_limit(count + 1, limits),
         :ok <- attributes(field(record, "attributes"), limits, true),
         :ok <- body_structure(field(record, "body"), limits) do
      {:ok, {count + 1, groups}}
    end
  end

  defp validate_metrics(payload, limits) do
    limits = %{limits | max_depth: min(limits.max_depth, 32)}

    with :ok <- otlp_nodes(payload, limits.max_otlp_nodes) do
      field(payload, "resourceMetrics")
      |> reduce_list({0, 0, 0}, &metric_resource(&1, limits, &2))
      |> finish()
    end
  end

  defp metric_resource(owner, limits, {count, groups, exemplars}) do
    with :ok <- metric_group_limit(groups + 1, limits),
         :ok <- attributes(field(field(owner, "resource"), "attributes"), limits, true) do
      reduce_list(field(owner, "scopeMetrics"), {count, groups + 1, exemplars}, &metric_scope(&1, limits, &2))
    end
  end

  defp metric_scope(owner, limits, {count, groups, exemplars}) do
    with :ok <- metric_group_limit(groups + 1, limits),
         :ok <- attributes(field(field(owner, "scope"), "attributes"), limits, true) do
      reduce_list(field(owner, "metrics"), {count, groups + 1, exemplars}, &metric_descriptor(&1, limits, &2))
    end
  end

  defp metric_descriptor(owner, limits, {count, groups, exemplars}) do
    with :ok <- metric_group_limit(groups + 1, limits),
         :ok <- attributes(field(owner, "metadata"), limits, true),
         :ok <- descriptor_strings(owner, limits) do
      reduce_list(~w(gauge sum histogram exponentialHistogram summary), {count, groups + 1, exemplars}, fn kind,
                                                                                                           state ->
        reduce_list(field(field(owner, kind), "dataPoints"), state, &metric_point(&1, limits, &2))
      end)
    end
  end

  defp descriptor_strings(owner, limits) do
    Enum.reduce_while(~w(name description unit), :ok, fn key, :ok ->
      case walk(field(owner, key), limits, 0, {0, 0}) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp metric_point(owner, limits, {count, groups, exemplars}) do
    with :ok <- record_limit(count + 1, limits),
         :ok <- attributes(field(owner, "attributes"), limits, true),
         {:ok, exemplars} <- metric_exemplars(field(owner, "exemplars"), limits, exemplars),
         :ok <- metric_double(field(owner, "asDouble"), limits) do
      {:ok, {count + 1, groups, exemplars}}
    end
  end

  defp metric_exemplars(values, limits, count) do
    reduce_list(values, count, fn owner, count ->
      with :ok <- record_limit(count + 1, limits),
           :ok <- attributes(field(owner, "filteredAttributes"), limits, true),
           :ok <- metric_double(field(owner, "asDouble"), limits),
           do: {:ok, count + 1}
    end)
  end

  defp metric_double(value, limits), do: value |> walk_double(limits, 0, {0, 0}) |> finish()
  defp metric_group_limit(count, limits), do: record_limit(count, %{limits | max_records: 3 * limits.max_records})

  # Protobuf enforces this before constructing intermediate maps; JSON also
  # counts the supplied tree, including unknown fields and duplicate pairs.
  defp validate_traces(payload, limits) do
    with {:ok, _remaining} <- trace_nodes(payload, limits.max_trace_nodes) do
      field(payload, "resourceSpans")
      |> reduce_list({0, 0, 0, 0}, &trace_resource(&1, limits, &2))
      |> finish()
    end
  end

  defp otlp_nodes(payload, limit) do
    case trace_nodes(payload, limit) do
      {:ok, _} -> :ok
      {:error, :too_many_trace_nodes} -> {:error, :too_many_otlp_nodes}
    end
  end

  defp trace_nodes(_, 0), do: {:error, :too_many_trace_nodes}

  defp trace_nodes(value, remaining) when is_map(value) do
    reduce_list_value(value, remaining - 1, fn {_key, child}, left -> trace_nodes(child, left) end)
  end

  defp trace_nodes(value, remaining) when is_list(value) do
    reduce_list_value(value, remaining - 1, &trace_nodes/2)
  end

  defp trace_nodes(_, remaining), do: {:ok, remaining - 1}

  defp reduce_list_value(values, remaining, fun) do
    Enum.reduce_while(values, {:ok, remaining}, fn child, {:ok, left} ->
      case fun.(child, left) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp trace_resource(resource, limits, {count, groups, events, links}) do
    with :ok <- otlp_group_limit(groups + 1, limits),
         :ok <- attributes(field(field(resource, "resource"), "attributes"), limits, true) do
      reduce_list(field(resource, "scopeSpans"), {count, groups + 1, events, links}, &trace_scope(&1, limits, &2))
    end
  end

  defp trace_scope(scope, limits, {count, groups, events, links}) do
    with :ok <- otlp_group_limit(groups + 1, limits),
         :ok <- attributes(field(field(scope, "scope"), "attributes"), limits, true) do
      reduce_list(field(scope, "spans"), {count, groups + 1, events, links}, &trace_span(&1, limits, &2))
    end
  end

  defp trace_span(span, limits, {count, groups, events, links}) do
    with :ok <- record_limit(count + 1, limits),
         :ok <- attributes(field(span, "attributes"), limits, true),
         {:ok, events} <- trace_children(field(span, "events"), limits, events),
         {:ok, links} <- trace_children(field(span, "links"), limits, links) do
      {:ok, {count + 1, groups, events, links}}
    end
  end

  defp trace_children(children, limits, count) do
    reduce_list(children, count, fn child, count ->
      with :ok <- record_limit(count + 1, limits),
           :ok <- attributes(field(child, "attributes"), limits, true) do
        {:ok, count + 1}
      end
    end)
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key)
  defp field(_, _), do: nil

  defp reduce_list(list, initial, fun) when is_list(list) do
    Enum.reduce_while(list, {:ok, initial}, fn item, {:ok, state} ->
      case fun.(item, state) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp reduce_list(_, initial, _), do: {:ok, initial}
  defp finish({:ok, _}), do: :ok
  defp finish(error), do: error

  defp record_limit(count, limits) do
    if count <= limits.max_records, do: :ok, else: {:error, :too_many_records}
  end

  # Empty containers also consume work, independently of record count.
  defp group_limit(count, limits), do: record_limit(count, limits)

  # A single OTLP record needs both a resource and a scope group.
  defp otlp_group_limit(count, limits), do: record_limit(count, %{limits | max_records: 2 * limits.max_records})

  defp attributes(nil, _, _), do: :ok

  defp attributes(value, limits, true) do
    value |> otlp_pairs(limits, 0, {0, 0}) |> finish()
  end

  defp attributes(value, limits, false) do
    with :ok <- attribute_count(value, limits),
         {:ok, _} <- walk(value, limits, 0, {0, 0}) do
      :ok
    end
  end

  defp otlp_pairs(pairs, limits, depth, {bytes, nodes}) when is_list(pairs) do
    with :ok <- structure_limit(limits, depth, nodes),
         :ok <- attribute_count(pairs, limits) do
      reduce_list(pairs, {bytes, nodes + 1}, &otlp_pair(&1, limits, depth, &2))
    end
  end

  defp otlp_pairs(value, limits, depth, state), do: walk(value, limits, depth, state)

  defp otlp_pair(pair, limits, depth, state) do
    with {:ok, next} <- walk_attribute_key(field(pair, "key"), limits, depth + 1, state) do
      walk_otlp(field(pair, "value"), limits, depth + 1, next)
    end
  end

  defp walk_attribute_key(key, limits, depth, {bytes, nodes}) when is_binary(key) do
    with :ok <- structure_limit(limits, depth, nodes),
         :ok <- key_limit(key, limits) do
      add_bytes({bytes, nodes + 1}, byte_size(key), limits)
    end
  end

  defp walk_attribute_key(key, limits, depth, state), do: walk(key, limits, depth, state)

  defp walk_otlp(value, limits, depth, state) when is_map(value) do
    # Invalid JSON oneofs must not hide oversized supplied members behind the
    # first recognized key. Protobuf preflight likewise visits every member.
    fields = Map.take(value, ~w(stringValue boolValue intValue doubleValue bytesValue arrayValue kvlistValue))
    assigned = Enum.reject(fields, fn {_key, value} -> is_nil(value) end)

    case assigned do
      [] ->
        walk_otlp_member(if(map_size(fields) > 0, do: %{}, else: value), limits, depth, state)

      _ ->
        reduce_list_value(assigned, state, fn {key, member}, state ->
          walk_otlp_member(%{key => member}, limits, depth, state)
        end)
    end
  end

  defp walk_otlp(value, limits, depth, state), do: walk_otlp_member(value, limits, depth, state)

  defp walk_otlp_member(value, limits, depth, {_, nodes} = state) do
    with :ok <- structure_limit(limits, depth, nodes) do
      case value do
        %{"stringValue" => v} ->
          walk(v, limits, depth, state)

        %{"boolValue" => v} ->
          walk(v, limits, depth, state)

        %{"doubleValue" => v} ->
          walk_double(v, limits, depth, state)

        %{"bytesValue" => v} ->
          walk(v, limits, depth, state)

        %{"intValue" => v} ->
          walk(v, limits, depth, state)

        %{"arrayValue" => %{"values" => values}} when is_list(values) ->
          {bytes, nodes} = state
          reduce_list(values, {bytes, nodes + 1}, &walk_otlp(&1, limits, depth + 1, &2))

        %{"kvlistValue" => %{"values" => pairs}} when is_list(pairs) ->
          otlp_pairs(pairs, limits, depth, state)

        other ->
          walk(other, limits, depth, state)
      end
    end
  end

  defp walk_double(value, _limits, _depth, _state) when is_binary(value) and byte_size(value) > 1024,
    do: {:error, :attributes_too_large}

  defp walk_double(value, limits, depth, state), do: walk(value, limits, depth, state)

  defp attribute_count(value, limits) when is_map(value) do
    if map_size(value) <= limits.max_attributes, do: :ok, else: {:error, :attributes_too_large}
  end

  defp attribute_count(value, limits) when is_list(value) do
    value
    |> Enum.reduce_while(0, fn _, count ->
      if count < limits.max_attributes, do: {:cont, count + 1}, else: {:halt, :over}
    end)
    |> case do
      :over -> {:error, :attributes_too_large}
      _ -> :ok
    end
  end

  defp attribute_count(_, _), do: :ok

  # Bodies can contain AnyValue recursion too. Bound structure without applying
  # the attribute string/byte caps to ordinary log messages.
  defp body_structure(value, limits) do
    body_limits = %{limits | max_value_bytes: 16 * 1024 * 1024, max_attribute_bytes: 16 * 1024 * 1024}
    value |> walk_otlp(body_limits, 0, {0, 0}) |> finish()
  end

  defp structure_limit(limits, depth, nodes) do
    if depth <= limits.max_depth and nodes < limits.max_nodes,
      do: :ok,
      else: {:error, :attributes_too_large}
  end

  defp walk(_, limits, depth, {_, nodes}) when depth > limits.max_depth or nodes >= limits.max_nodes,
    do: {:error, :attributes_too_large}

  defp walk(value, limits, depth, {bytes, nodes}) do
    state = {bytes, nodes + 1}

    cond do
      is_binary(value) ->
        walk_string(value, limits, state)

      is_map(value) ->
        with :ok <- attribute_count(value, limits) do
          reduce_map(value, state, &walk_map_entry(&1, limits, depth, &2))
        end

      is_list(value) ->
        reduce_list(value, state, &walk(&1, limits, depth + 1, &2))

      true ->
        add_bytes(state, 8, limits)
    end
  end

  defp walk_string(value, limits, state) do
    if byte_size(value) <= limits.max_value_bytes,
      do: add_bytes(state, byte_size(value), limits),
      else: {:error, :attributes_too_large}
  end

  defp walk_map_entry({key, child}, limits, depth, state) do
    with :ok <- key_limit(key, limits),
         {:ok, next} <- add_bytes(state, if(is_binary(key), do: byte_size(key), else: 8), limits) do
      walk(child, limits, depth + 1, next)
    end
  end

  defp reduce_map(map, state, fun) do
    Enum.reduce_while(map, {:ok, state}, fn pair, {:ok, state} ->
      case fun.(pair, state) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp key_limit(key, limits) when is_binary(key) and byte_size(key) > limits.max_key_bytes,
    do: {:error, :attributes_too_large}

  defp key_limit(_, _), do: :ok

  defp add_bytes({bytes, nodes}, amount, limits) do
    if bytes + amount <= limits.max_attribute_bytes,
      do: {:ok, {bytes + amount, nodes}},
      else: {:error, :attributes_too_large}
  end
end
