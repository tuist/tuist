defmodule Atlas.Automations.Composition do
  @moduledoc "Conservative publication checks; dynamic and open-schema values still validate at execution."
  alias Atlas.Automations.Contract

  def validate(value, schema, steps) do
    outputs = Map.new(steps, fn step -> {step["id"], get_in(step, ["behavior", "output_schema"])} end)
    check(value, schema, outputs)
  end

  defp check(%{"$ref" => path} = value, target, outputs) when map_size(value) == 1 do
    case String.split(path, ".") do
      ["steps", id | fields] ->
        with {:ok, source} <- field_schema(outputs[id], fields), do: compatible(source, target)

      _ ->
        :ok
    end
  end

  defp check(value, schema, outputs) when is_map(value) do
    if references?(value) do
      check_object(value, schema, outputs)
    else
      validate_literal(schema, value)
    end
  end

  defp check(value, schema, outputs) when is_list(value) do
    if references?(value) do
      Enum.reduce_while(value, :ok, fn child, _ ->
        case check(child, schema["items"] || %{}, outputs) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      validate_literal(schema, value)
    end
  end

  defp check(value, schema, _outputs), do: validate_literal(schema, value)

  defp check_object(value, schema, outputs) do
    properties = schema["properties"] || %{}
    unknown = Map.keys(value) -- Map.keys(properties)
    missing = (schema["required"] || []) -- Map.keys(value)

    if missing != [] or (schema["additionalProperties"] == false and unknown != []) do
      {:error, "Step inputs do not match the registered fields."}
    else
      Enum.reduce_while(value, :ok, fn {key, child}, _ ->
        case check(child, properties[key] || %{}, outputs) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp validate_literal(schema, value) do
    # Wrap scalar/array fragments so the shared bounded object validator remains authoritative.
    Contract.validate(%{"type" => "object", "properties" => %{"value" => schema}, "required" => ["value"]}, %{
      "value" => value
    })
  end

  defp field_schema(nil, _), do: {:ok, %{}}
  defp field_schema(schema, []), do: {:ok, schema}

  defp field_schema(schema, [key | rest]) do
    case get_in(schema, ["properties", key]) do
      nil ->
        if schema["additionalProperties"] == false,
          do: {:error, "A referenced output field is not in the pinned behavior contract."},
          else: {:ok, %{}}

      child ->
        field_schema(child, rest)
    end
  end

  defp compatible(source, target) do
    source_types = List.wrap(source["type"])
    target_types = List.wrap(target["type"])
    source_types = if "integer" in source_types, do: ["number" | source_types], else: source_types

    if source_types == [] or target_types == [] or Enum.any?(source_types, &(&1 in target_types)),
      do: :ok,
      else: {:error, "A referenced output type is incompatible with the receiving input field."}
  end

  defp references?(%{"$ref" => _}), do: true
  defp references?(value) when is_map(value), do: Enum.any?(Map.values(value), &references?/1)
  defp references?(value) when is_list(value), do: Enum.any?(value, &references?/1)
  defp references?(_), do: false
end
