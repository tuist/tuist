defmodule Pulse.MCP.Arguments do
  @moduledoc false

  # Validate the schema vocabulary used by Pulse's tool registry. Keeping
  # validation tied to the published schemas prevents discovery and calls
  # from disagreeing about types, required fields, or numeric limits.
  def normalize(value, schema) do
    required = schema["required"] || []

    Enum.reduce(schema["properties"] || %{}, value, fn {key, child_schema}, args ->
      normalize_property(args, key, child_schema, required)
    end)
  end

  defp normalize_property(args, key, schema, required) do
    case Map.fetch(args, key) do
      {:ok, nil} -> if key in required, do: args, else: Map.delete(args, key)
      {:ok, value} -> Map.put(args, key, normalize_integer(value, schema))
      :error -> args
    end
  end

  defp normalize_integer(value, %{"type" => "integer"}) when is_float(value) do
    integer = trunc(value)
    if value == integer, do: integer, else: value
  end

  defp normalize_integer(value, _schema), do: value

  def validate(value, schema, path \\ "arguments") do
    with :ok <- validate_type(value, schema["type"], path),
         :ok <- validate_constraints(value, schema, path) do
      validate_children(value, schema, path)
    end
  end

  defp validate_type(value, "object", _path) when is_map(value), do: :ok
  defp validate_type(value, "array", _path) when is_list(value), do: :ok
  defp validate_type(value, "string", _path) when is_binary(value), do: :ok
  defp validate_type(value, "integer", _path) when is_integer(value), do: :ok
  defp validate_type(value, "boolean", _path) when is_boolean(value), do: :ok
  defp validate_type(_value, type, path), do: invalid("#{path} must be #{type}")

  defp validate_constraints(value, schema, path) do
    with :ok <- validate_enum(value, schema, path),
         :ok <- validate_bounds(value, schema, path) do
      validate_length(value, schema, path)
    end
  end

  defp validate_enum(value, %{"enum" => allowed}, path) do
    if value in allowed, do: :ok, else: invalid("#{path} must be one of #{inspect(allowed)}")
  end

  defp validate_enum(_value, _schema, _path), do: :ok

  defp validate_bounds(value, schema, path) when is_integer(value) do
    cond do
      Map.has_key?(schema, "minimum") and value < schema["minimum"] ->
        invalid("#{path} must be at least #{schema["minimum"]}")

      Map.has_key?(schema, "maximum") and value > schema["maximum"] ->
        invalid("#{path} must be at most #{schema["maximum"]}")

      true ->
        :ok
    end
  end

  defp validate_bounds(_value, _schema, _path), do: :ok

  defp validate_length(value, schema, path) when is_binary(value) do
    length = codepoint_length(value, 0)

    cond do
      length == :invalid ->
        invalid("#{path} must contain valid UTF-8")

      Map.has_key?(schema, "minLength") and length < schema["minLength"] ->
        invalid("#{path} must contain at least #{schema["minLength"]} characters")

      Map.has_key?(schema, "maxLength") and length > schema["maxLength"] ->
        invalid("#{path} must contain at most #{schema["maxLength"]} characters")

      true ->
        :ok
    end
  end

  defp validate_length(value, %{"maxItems" => maximum}, path) when is_list(value) do
    if length(Enum.take(value, maximum + 1)) <= maximum,
      do: :ok,
      else: invalid("#{path} must contain at most #{maximum} items")
  end

  defp validate_length(_value, _schema, _path), do: :ok

  # JSON Schema lengths count code points, not grapheme clusters. Walk
  # without allocating a charlist proportional to an untrusted string.
  defp codepoint_length(<<>>, count), do: count
  defp codepoint_length(<<_::utf8, rest::binary>>, count), do: codepoint_length(rest, count + 1)
  defp codepoint_length(_invalid, _count), do: :invalid

  defp validate_children(value, %{"type" => "object"} = schema, path) do
    with :ok <- validate_required(value, schema, path),
         :ok <- validate_object_bounds(value, schema, path),
         :ok <- validate_property_names(value, schema, path),
         :ok <- validate_additional_properties(value, schema, path) do
      Enum.reduce_while(schema["properties"] || %{}, :ok, fn {key, child_schema}, :ok ->
        continue(validate_property(value, key, child_schema, path))
      end)
    end
  end

  defp validate_children(value, %{"type" => "array", "items" => schema}, path) do
    value
    |> Stream.with_index()
    |> Enum.reduce_while(:ok, fn {child, index}, :ok ->
      continue(validate(child, schema, "#{path}[#{index}]"))
    end)
  end

  defp validate_children(_value, _schema, _path), do: :ok

  defp validate_additional_properties(value, %{"additionalProperties" => false} = schema, path) do
    properties = schema["properties"] || %{}

    case Enum.find(Map.keys(value), &(not Map.has_key?(properties, &1))) do
      nil -> :ok
      unknown -> invalid("#{path}.#{unknown} is not supported")
    end
  end

  defp validate_additional_properties(value, %{"additionalProperties" => child_schema} = schema, path)
       when is_map(child_schema) do
    properties = schema["properties"] || %{}

    Enum.reduce_while(value, :ok, fn {key, child}, :ok ->
      if Map.has_key?(properties, key),
        do: {:cont, :ok},
        else: continue(validate(child, child_schema, "#{path}.#{key}"))
    end)
  end

  defp validate_additional_properties(_value, _schema, _path), do: :ok

  defp validate_object_bounds(value, %{"maxProperties" => maximum}, path) do
    if map_size(value) <= maximum, do: :ok, else: invalid("#{path} must contain at most #{maximum} properties")
  end

  defp validate_object_bounds(_value, _schema, _path), do: :ok

  defp validate_property_names(value, %{"propertyNames" => schema}, path) do
    Enum.reduce_while(Map.keys(value), :ok, fn key, :ok -> continue(validate(key, schema, "#{path} property name")) end)
  end

  defp validate_property_names(_value, _schema, _path), do: :ok

  defp validate_required(value, schema, path) do
    case Enum.find(schema["required"] || [], &(not Map.has_key?(value, &1))) do
      nil -> :ok
      missing -> invalid("#{path}.#{missing} is required")
    end
  end

  defp validate_property(value, key, schema, path) do
    case Map.fetch(value, key) do
      :error -> :ok
      {:ok, child} -> validate(child, schema, "#{path}.#{key}")
    end
  end

  defp continue(:ok), do: {:cont, :ok}
  defp continue(error), do: {:halt, error}
  defp invalid(message), do: {:error, {:invalid_arguments, message}}
end
