defmodule Pulse.Record.SpanKey do
  @moduledoc false

  # Reference for the native trace selector's metadata key. Unlike external
  # term format, this can also be built directly from JSON before allocating
  # Erlang maps. It preserves scalar types, float bits, and nested structure.
  alias Pulse.Record.Span

  def encode(value), do: value |> value_key() |> IO.iodata_to_binary()

  @span_fields Map.keys(%Span{}) -- [:__struct__]
  @span_key_sizes Map.new(@span_fields, &{&1, 5 + byte_size(Atom.to_string(&1))})

  # Same encoded size without constructing keys/iodata during every merge.
  def size(%Span{} = span) do
    Enum.reduce(@span_key_sizes, 5, fn {field, key_size}, sum ->
      if field == :otlp and is_nil(span.otlp), do: sum, else: sum + key_size + size(Map.fetch!(span, field))
    end)
  end

  def size(value) when is_nil(value) or is_boolean(value), do: 1
  def size(value) when is_integer(value), do: 6 + byte_size(:binary.encode_unsigned(abs(value)))
  def size(value) when is_float(value), do: 9
  def size(value) when is_binary(value), do: 5 + byte_size(value)
  def size(value) when is_list(value), do: Enum.reduce(value, 5, &(&2 + size(&1)))

  def size(value) when is_map(value),
    do: Enum.reduce(value, 5, fn {key, value}, sum -> sum + size(key) + size(value) end)

  defp value_key(nil), do: <<0>>
  defp value_key(false), do: <<1>>
  defp value_key(true), do: <<2>>

  defp value_key(value) when is_integer(value) do
    magnitude = :binary.encode_unsigned(abs(value))
    [<<3, if(value < 0, do: 1, else: 0), byte_size(magnitude)::32>>, magnitude]
  end

  defp value_key(value) when is_float(value), do: <<4, value::float-64>>
  defp value_key(value) when is_binary(value), do: [<<5, byte_size(value)::32>>, value]

  defp value_key(value) when is_list(value) do
    [<<6, length(value)::32>>, Enum.map(value, &value_key/1)]
  end

  defp value_key(value) when is_map(value) do
    entries = Enum.sort_by(value, fn {key, _} -> key end)
    [<<7, map_size(value)::32>>, Enum.map(entries, fn {key, value} -> [value_key(key), value_key(value)] end)]
  end
end
