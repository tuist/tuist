defmodule Pulse.Traces.RegexFilters do
  @moduledoc false
  alias Pulse.Codec.NIF

  @fields ["attributes_regex", "resource_regex"]

  def validate(args) do
    entries = Enum.flat_map(@fields, fn field -> Map.to_list(args[field] || %{}) end)

    if length(entries) <= 8 and Enum.all?(entries, &valid?/1),
      do: :ok,
      else: {:error, {:invalid_arguments, "trace regex filters require at most 8 valid bounded string patterns"}}
  end

  def matches?(span, opts) do
    Enum.all?([{:attributes_regex, span.attributes}, {:resource_regex, span.resource}], fn {field, values} ->
      Enum.all?(Keyword.get(opts, field, %{}), fn {key, pattern} ->
        matches_value?(Map.get(values, key), pattern)
      end)
    end)
  end

  defp matches_value?(value, pattern) when is_binary(value), do: NIF.match_metric_regex(anchored(pattern), value)
  defp matches_value?(_, _), do: false

  defp valid?({key, pattern}) when is_binary(key) and is_binary(pattern) do
    byte_size(key) in 1..256 and byte_size(pattern) <= 1024 and String.valid?(key) and String.valid?(pattern) and
      NIF.validate_metric_regex(pattern) == :ok and NIF.validate_metric_regex(anchored(pattern)) == :ok
  end

  defp valid?(_), do: false
  defp anchored(pattern), do: Pulse.QueryRegex.anchor(pattern)
end
