defmodule Atlas.Automations.Contract do
  @moduledoc false

  def validate_schema(schema) when is_map(schema) do
    if schema["type"] == "object" and within_budget?(schema, 16_384) and not contains_reference?(schema) do
      ExJsonSchema.Schema.resolve(schema)
      :ok
    else
      {:error, "Schemas must describe an object, be at most 16 KiB, and contain no schema references."}
    end
  rescue
    _ -> {:error, "Invalid JSON Schema."}
  end

  def validate_schema(_), do: {:error, "A JSON object schema is required."}

  def validate(schema, value) do
    with :ok <- validate_schema(schema),
         true <- is_map(value) and within_budget?(value, 65_536),
         :ok <- schema |> ExJsonSchema.Schema.resolve() |> ExJsonSchema.Validator.validate(value) do
      :ok
    else
      _ -> {:error, "Value does not match its object contract or exceeds 64 KiB."}
    end
  rescue
    _ -> {:error, "Value does not match its object contract."}
  end

  # Walk with a shrinking budget before encoding: references can share a large
  # value thousands of times, making an otherwise small term expensive to encode.
  def within_budget?(value, bytes), do: remaining(value, bytes, 0) >= 0

  defp remaining(_value, bytes, _depth) when bytes < 0, do: -1
  defp remaining(_value, _bytes, depth) when depth > 32, do: -1

  defp remaining(value, bytes, depth) when is_map(value) do
    Enum.reduce_while(value, bytes - 2, fn {key, item}, budget ->
      next = if is_binary(key), do: remaining(item, remaining(key, budget - 2, depth + 1), depth + 1), else: -1
      if next < 0, do: {:halt, -1}, else: {:cont, next}
    end)
  end

  defp remaining(value, bytes, depth) when is_list(value) do
    Enum.reduce_while(value, bytes - 2, fn item, budget ->
      next = remaining(item, budget - 1, depth + 1)
      if next < 0, do: {:halt, -1}, else: {:cont, next}
    end)
  end

  defp remaining(value, bytes, _depth) when is_binary(value) do
    if byte_size(value) > bytes, do: -1, else: bytes - byte_size(JSON.encode!(value))
  end

  defp remaining(value, bytes, _depth) when is_number(value) or value in [true, false, nil],
    do: bytes - byte_size(JSON.encode!(value))

  defp remaining(_, _, _), do: -1

  defp contains_reference?(value) when is_map(value) do
    Map.has_key?(value, "$ref") or Enum.any?(Map.values(value), &contains_reference?/1)
  end

  defp contains_reference?(value) when is_list(value), do: Enum.any?(value, &contains_reference?/1)
  defp contains_reference?(_), do: false
end
