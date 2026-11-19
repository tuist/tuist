defmodule Tuist.Pulse.OTLP do
  @moduledoc """
  OTLP/HTTP payloads (https://opentelemetry.io/docs/specs/otlp/#otlphttp):
  export requests in either encoding OTLP/HTTP allows, decoded into the maps
  of the gpb codecs `opentelemetry_exporter` generates for its own exports, so
  this module follows that dependency's OTLP version rather than vendoring the
  protos again; and the responses a receiver answers with, in the request's
  encoding.

  OTLP/JSON is the proto3 JSON mapping with OTLP's deviations: trace and span
  IDs as hex, other bytes as base64, 64-bit integers as numbers or decimal
  strings, and enums as integers (their names are accepted too). Field names
  may be lowerCamelCase or snake_case, and unknown fields are ignored, as the
  specification asks of receivers. Enums decode to their symbols; in JSON an
  integer no symbol has is invalid, while protobuf keeps it as the integer, as
  gpb does, so callers that store enums must check them.
  """

  @signals %{
    "traces" =>
      {:opentelemetry_exporter_trace_service_pb, :export_trace_service_request, :export_trace_service_response,
       :export_trace_partial_success, :rejected_spans},
    "logs" =>
      {:opentelemetry_exporter_logs_service_pb, :export_logs_service_request, :export_logs_service_response,
       :export_logs_partial_success, :rejected_log_records},
    "metrics" =>
      {:opentelemetry_exporter_metrics_service_pb, :export_metrics_service_request, :export_metrics_service_response,
       :export_metrics_partial_success, :rejected_data_points}
  }

  # OTLP/JSON writes these bytes fields as hex and every other one as base64.
  @hex_fields [:trace_id, :span_id, :parent_span_id]
  @integers [:int32, :int64, :uint32, :uint64, :sint32, :sint64, :fixed32, :fixed64, :sfixed32, :sfixed64]

  def signals, do: Map.keys(@signals)

  @doc """
  Decodes an export request for `signal` (`traces`, `logs` or `metrics`):
  `{:json, map}` for OTLP/JSON already parsed, `{:protobuf, binary}` for binary
  protobuf. Returns `{:ok, request}` or `{:error, :invalid}`.
  """
  def decode(signal, {:json, json}) when is_map(json) do
    {module, name, _, _, _} = Map.fetch!(@signals, signal)
    {:ok, message(module, name, json)}
  catch
    :throw, :invalid -> {:error, :invalid}
  end

  def decode(signal, {:protobuf, body}) when is_binary(body) do
    {module, name, _, _, _} = Map.fetch!(@signals, signal)
    {:ok, module.decode_msg(body, name)}
  rescue
    _error -> {:error, :invalid}
  end

  def decode(_signal, _payload), do: {:error, :invalid}

  @doc "Encodes `request` as protobuf. Returns `{:ok, binary}` or `{:error, :invalid}`."
  def encode(signal, request) do
    {module, name, _, _, _} = Map.fetch!(@signals, signal)
    {:ok, module.encode_msg(request, name, verify: true)}
  rescue
    # gpb's verification raises on values out of range for their type.
    _error -> {:error, :invalid}
  end

  @doc """
  The success response for `signal` in `format` (`:json` or `:protobuf`).
  When the receiver dropped `rejected` records it is a partial success saying
  why in `message`; otherwise `partial_success` is unset, as the
  specification requires of a full success.
  """
  def response(signal, format, rejected \\ 0, message \\ "")

  def response(_signal, :json, 0, _message), do: "{}"

  def response(signal, :json, rejected, message) do
    {_, _, _, _, field} = Map.fetch!(@signals, signal)
    # The proto3 JSON mapping writes 64-bit integers as decimal strings.
    JSON.encode!(%{"partialSuccess" => %{camel(field) => Integer.to_string(rejected), "errorMessage" => message}})
  end

  def response(signal, :protobuf, rejected, message) do
    {module, _, name, _, field} = Map.fetch!(@signals, signal)
    partial = if rejected == 0, do: %{}, else: %{partial_success: %{field => rejected, error_message: message}}
    module.encode_msg(partial, name)
  end

  @doc """
  The records a protobuf success response for `signal` says were rejected,
  with its message: `{0, \"\"}` for a full success or a body that isn't one.
  """
  def rejected(signal, body) do
    {module, _, name, _, field} = Map.fetch!(@signals, signal)

    case module.decode_msg(body, name) do
      %{partial_success: %{} = partial} -> {Map.get(partial, field, 0), Map.get(partial, :error_message, "")}
      _ -> {0, ""}
    end
  rescue
    _error -> {0, ""}
  end

  @doc """
  A failure response body: the `google.rpc.Status` the specification asks
  for, with `code` (a gRPC status code) and `message`.
  """
  def status(:json, code, message), do: JSON.encode!(%{"code" => code, "message" => message})

  # Status { int32 code = 1; string message = 2; }: no codec ships it, and
  # two scalar fields need none.
  def status(:protobuf, code, message),
    do: IO.iodata_to_binary([0x08, varint(code), 0x12, varint(byte_size(message)), message])

  defp varint(n) when n < 128, do: n
  defp varint(n), do: [Bitwise.bor(Bitwise.band(n, 127), 128), varint(Bitwise.bsr(n, 7))]

  defp camel(field) do
    [first | rest] = field |> Atom.to_string() |> String.split("_")
    first <> Enum.map_join(rest, &String.capitalize/1)
  end

  defp message(module, name, json) when is_map(json) do
    name |> module.find_msg_def() |> Enum.reduce(%{}, &put_field(&2, module, &1, json))
  end

  defp message(_module, _name, _json), do: throw(:invalid)

  # A oneof, such as AnyValue's value: the first member present.
  defp put_field(acc, module, %{name: name, fields: members}, json) do
    case Enum.find_value(members, &with_value(&1, json)) do
      nil -> acc
      {member, value} -> Map.put(acc, name, {member.name, value(module, member, value)})
    end
  end

  defp put_field(acc, module, %{name: name, occurrence: :repeated} = field, json) do
    case fetch(json, name) do
      nil -> acc
      values when is_list(values) -> Map.put(acc, name, Enum.map(values, &value(module, field, &1)))
      _ -> throw(:invalid)
    end
  end

  defp put_field(acc, module, %{name: name} = field, json) do
    case fetch(json, name) do
      nil -> acc
      value -> Map.put(acc, name, value(module, field, value))
    end
  end

  defp with_value(field, json) do
    case fetch(json, field.name) do
      nil -> nil
      value -> {field, value}
    end
  end

  defp fetch(json, name) do
    case Map.fetch(json, camel(name)) do
      {:ok, value} -> value
      :error -> Map.get(json, Atom.to_string(name))
    end
  end

  defp value(module, %{type: {:msg, name}}, value), do: message(module, name, value)

  defp value(module, %{type: {:enum, enum}}, value) when is_integer(value) or is_binary(value) do
    # gpb lists each value as `{symbol, number, options}`.
    Enum.find_value(module.find_enum_def(enum), fn definition ->
      {symbol, number} = {elem(definition, 0), elem(definition, 1)}
      (number == value or Atom.to_string(symbol) == value) && symbol
    end) || throw(:invalid)
  end

  defp value(_module, %{type: :string}, value) when is_binary(value), do: value
  defp value(_module, %{type: :bool}, value) when is_boolean(value), do: value
  defp value(_module, %{type: type}, value) when type in [:double, :float] and is_number(value), do: value
  defp value(_module, %{type: type}, value) when type in @integers and is_integer(value), do: value

  defp value(_module, %{type: type}, value) when type in @integers and is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> throw(:invalid)
    end
  end

  defp value(_module, %{type: :bytes, name: name}, value) when name in @hex_fields and is_binary(value),
    do: decoded(Base.decode16(value, case: :mixed))

  defp value(_module, %{type: :bytes}, value) when is_binary(value), do: decoded(Base.decode64(value))
  defp value(_module, _field, _value), do: throw(:invalid)

  defp decoded({:ok, bytes}), do: bytes
  defp decoded(:error), do: throw(:invalid)
end
