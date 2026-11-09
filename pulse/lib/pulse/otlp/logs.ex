defmodule Pulse.OTLP.Logs do
  @moduledoc "Decode bounded OTLP JSON/protobuf logs, preserving typed values and resource/scope metadata."
  alias Pulse.Codec.NIF
  alias Pulse.OTLP.Traces
  alias Pulse.OTLP.Value
  alias Pulse.Record.Log

  @max_timestamp 9_223_372_036_854_775_807
  @max_count 4_294_967_295
  @payload_bytes 16_777_216

  def decode(%{} = payload) do
    with :ok <- Pulse.IngestLimits.validate(:otlp, payload),
         resources when is_list(resources) <- Value.field(payload, "resourceLogs", []),
         {:ok, records, rejected} <- resources(resources),
         records = Enum.reverse(records),
         {:ok, _bytes} <- NIF.log_payload_size(records, @payload_bytes) do
      {:ok, records, rejected}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_otlp}
    end
  end

  def decode(_), do: {:error, :invalid_otlp}

  def decode_protobuf(body) do
    l = Pulse.IngestLimits.config()

    limits =
      {l.max_records, l.max_attributes, l.max_key_bytes, l.max_value_bytes, l.max_attribute_bytes, min(l.max_depth, 32),
       l.max_nodes, l.max_otlp_nodes}

    case NIF.decode_otlp_logs(body, limits) do
      {:ok, payload} -> decode(payload)
      error -> error
    end
  end

  @doc false
  def prepare(records, key) do
    if key != nil and Enum.any?(records, &is_nil(&1.timestamp_ns)) do
      {:error, :missing_keyed_timestamp}
    else
      now = System.system_time(:nanosecond)

      records =
        Enum.map(records, fn
          %{timestamp_ns: nil} = record ->
            %{record | timestamp_ns: now, otlp: Map.put(record.otlp, "receivedTimeUnixNano", Integer.to_string(now))}

          record ->
            record
        end)

      with {:ok, _} <- NIF.log_payload_size(records, @payload_bytes), do: {:ok, records}
    end
  end

  defp resources(resources) do
    Enum.reduce_while(resources, {:ok, [], 0}, fn resource, acc ->
      case resource(resource, acc) do
        {:ok, _, _} = next -> {:cont, next}
        _ -> {:halt, {:error, :invalid_otlp}}
      end
    end)
  end

  defp resource(%{} = owner, acc) do
    with {:ok, resource, typed} <- metadata(Value.field(owner, "resource", %{}), :resource),
         {:ok, schema} <- text(Value.field(owner, "schemaUrl", "")),
         scopes when is_list(scopes) <- Value.field(owner, "scopeLogs", []) do
      Enum.reduce_while(scopes, acc, &continue_scope(&1, resource, typed, schema, &2))
    end
  end

  defp resource(_, _), do: :error

  defp continue_scope(owner, resource, typed, schema, acc) do
    case scope(owner, resource, typed, schema, acc) do
      {:ok, _, _} = next -> {:cont, next}
      _ -> {:halt, :error}
    end
  end

  defp scope(%{} = owner, resource, typed, schema, {:ok, records, rejected}) do
    with {:ok, _scope_attrs, scope} <- metadata(Value.field(owner, "scope", %{}), :scope),
         {:ok, scope_schema} <- text(Value.field(owner, "schemaUrl", "")),
         logs when is_list(logs) <- Value.field(owner, "logRecords", []) do
      base = %Log{
        resource: resource,
        service: service(resource["service.name"]),
        otlp: %{
          "resource" => typed,
          "resourceSchemaUrl" => schema,
          "scope" => scope,
          "scopeSchemaUrl" => scope_schema
        }
      }

      Enum.reduce(logs, {:ok, records, rejected}, &collect(&1, base, &2))
    end
  end

  defp scope(_, _, _, _, _), do: :error

  defp metadata(%{} = owner, kind) do
    with true <- Value.field(owner, "entityRefs", []) == [],
         {:ok, attrs, typed} <- Value.attributes(owner),
         {:ok, count} <- Value.integer(Value.field(owner, "droppedAttributesCount", 0), 0, @max_count) do
      metadata = %{"attributes" => typed, "droppedAttributesCount" => count}

      complete_metadata(kind, owner, attrs, metadata)
    end
  end

  defp metadata(_, _), do: :error

  defp complete_metadata(:scope, owner, attrs, metadata) do
    with {:ok, name} <- text(Value.field(owner, "name", "")),
         {:ok, version} <- text(Value.field(owner, "version", "")),
         do: {:ok, attrs, Map.merge(metadata, %{"name" => name, "version" => version})}
  end

  defp complete_metadata(:resource, _, attrs, metadata), do: {:ok, attrs, metadata}

  defp collect(raw, base, {:ok, records, rejected}) do
    case record(raw, base) do
      {:ok, log} -> {:ok, [log | records], rejected}
      _ -> {:ok, records, rejected + 1}
    end
  end

  defp record(%{} = raw, base) do
    with {:ok, timestamp} <- timestamp(Value.field(raw, "timeUnixNano", 0)),
         {:ok, observed} <- timestamp(Value.field(raw, "observedTimeUnixNano", 0)),
         {:ok, severity} <- Value.integer(Value.field(raw, "severityNumber", 0), 0, 24),
         {:ok, severity_text} <- text(Value.field(raw, "severityText", "")),
         {:ok, event} <- text(Value.field(raw, "eventName", "")),
         {:ok, flags} <- Value.integer(Value.field(raw, "flags", 0), 0, @max_count),
         {:ok, dropped} <- Value.integer(Value.field(raw, "droppedAttributesCount", 0), 0, @max_count),
         {:ok, trace} <- id(Value.field(raw, "traceId", ""), 32),
         {:ok, span} <- id(Value.field(raw, "spanId", ""), 16),
         {:ok, attrs, typed_attrs} <- Value.attributes(raw),
         {:ok, body, typed_body} <- Value.decode(Value.field(raw, "body", %{})) do
      otlp =
        Map.merge(base.otlp, %{
          "timeUnixNano" => Integer.to_string(timestamp || 0),
          "observedTimeUnixNano" => Integer.to_string(observed || 0),
          "traceId" => original_id(Value.field(raw, "traceId", ""), trace),
          "spanId" => original_id(Value.field(raw, "spanId", ""), span),
          "body" => typed_body,
          "attributes" => typed_attrs,
          "flags" => flags,
          "droppedAttributesCount" => dropped,
          "eventName" => event
        })

      {:ok,
       %{
         base
         | timestamp_ns: timestamp || observed,
           observed_timestamp_ns: observed,
           severity_number: severity,
           severity_text: severity_text,
           trace_id: trace,
           span_id: span,
           attributes: attrs,
           body: body,
           otlp: otlp
       }}
    end
  end

  defp record(_, _), do: :error

  defp timestamp(value) do
    case Value.integer(value, 0, @max_timestamp) do
      {:ok, 0} -> {:ok, nil}
      result -> result
    end
  end

  defp id("", _length), do: {:ok, nil}

  defp id(value, length) when is_binary(value) do
    case Traces.id(value, length) do
      {:ok, _} = ok -> ok
      _ -> {:ok, nil}
    end
  end

  defp id(_, _), do: :error
  defp original_id(_raw, value) when is_binary(value), do: value
  defp original_id(raw, nil), do: Pulse.JSON.detach(raw)
  defp text(value) when is_binary(value), do: {:ok, Pulse.JSON.detach(value)}
  defp text(_), do: :error
  defp service(value) when is_binary(value), do: value
  defp service(_), do: nil
end
