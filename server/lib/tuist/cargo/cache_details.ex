defmodule Tuist.Cargo.CacheDetails do
  @moduledoc "Bounded public cache-task and CAS-operation inspection, without private agent events."

  alias OpenApiSpex.Schema

  @maximum 9_000_000_000_000_000
  @key_pattern "^(blake3|sha256):[0-9a-f]{64}:[0-9]{1,20}$"
  @task_keys ~w(key name kind status cas_keys read_duration_ns write_duration_ns)a
  @object_keys ~w(key operation status size_bytes duration_ns)a

  def schema do
    key = %Schema{type: :string, maxLength: 100, pattern: @key_pattern}
    duration = %Schema{type: :integer, minimum: 0, maximum: @maximum}

    %Schema{
      type: :object,
      additionalProperties: false,
      required: [:version, :tasks, :cas_outputs, :truncated],
      properties: %{
        version: %Schema{type: :integer, enum: [1]},
        truncated: %Schema{type: :boolean},
        tasks: %Schema{
          type: :array,
          maxItems: 2000,
          items: %Schema{
            type: :object,
            additionalProperties: false,
            required: [:key, :name, :kind, :status],
            properties: %{
              key: key,
              name: %Schema{type: :string, minLength: 1, maxLength: 1024},
              kind: %Schema{type: :string, enum: ["rust", "compiler", "build_script"]},
              status: %Schema{type: :string, enum: ["hit", "miss", "unconsulted", "verification"]},
              cas_keys: %Schema{type: :array, maxItems: 128, items: key},
              read_duration_ns: duration,
              write_duration_ns: duration
            }
          }
        },
        cas_outputs: %Schema{
          type: :array,
          maxItems: 5000,
          items: %Schema{
            type: :object,
            additionalProperties: false,
            required: @object_keys,
            properties: %{
              key: key,
              operation: %Schema{type: :string, enum: ["download", "upload"]},
              status: %Schema{type: :string, enum: ["downloaded", "uploaded", "present", "failed"]},
              size_bytes: duration,
              duration_ns: duration
            }
          }
        }
      }
    }
  end

  def normalize(nil), do: {:ok, nil}

  def normalize(details) when is_map(details) do
    with true <- allowed?(details, ~w(version tasks cas_outputs truncated)a),
         1 <- value(details, :version),
         truncated when is_boolean(truncated) <- value(details, :truncated),
         tasks when is_list(tasks) and length(tasks) <= 2000 <- value(details, :tasks),
         objects when is_list(objects) and length(objects) <= 5000 <- value(details, :cas_outputs),
         true <- Enum.all?(tasks, &valid_task?/1),
         true <- Enum.all?(objects, &valid_object?/1) do
      normalized = %{
        version: 1,
        truncated: truncated,
        tasks: Enum.map(tasks, &normalize_row(&1, @task_keys)),
        cas_outputs: Enum.map(objects, &normalize_row(&1, @object_keys))
      }

      if byte_size(JSON.encode!(normalized)) <= 4_000_000, do: {:ok, normalized}, else: {:error, :invalid_cache_details}
    else
      _ -> {:error, :invalid_cache_details}
    end
  end

  def normalize(_), do: {:error, :invalid_cache_details}

  defp valid_task?(task) when is_map(task) do
    allowed?(task, @task_keys) and valid_key?(value(task, :key)) and
      is_binary(value(task, :name)) and byte_size(value(task, :name)) in 1..1024 and
      value(task, :kind) in ["rust", "compiler", "build_script"] and
      value(task, :status) in ["hit", "miss", "unconsulted", "verification"] and
      optional?(value(task, :cas_keys), &valid_references?/1) and
      Enum.all?([:read_duration_ns, :write_duration_ns], fn key -> optional?(value(task, key), &valid_integer?/1) end)
  end

  defp valid_task?(_), do: false
  defp optional?(value, validator), do: is_nil(value) or validator.(value)

  defp valid_object?(object) when is_map(object) do
    allowed?(object, @object_keys) and valid_key?(value(object, :key)) and
      String.starts_with?(value(object, :key), "sha256:") and
      valid_integer?(value(object, :size_bytes)) and valid_integer?(value(object, :duration_ns)) and
      case value(object, :operation) do
        "download" -> value(object, :status) in ["downloaded", "failed"]
        "upload" -> value(object, :status) in ["uploaded", "present", "failed"]
        _ -> false
      end
  end

  defp valid_object?(_), do: false
  defp valid_references?(keys) when is_list(keys) and length(keys) <= 128, do: Enum.all?(keys, &valid_key?/1)
  defp valid_references?(_), do: false

  defp valid_key?(key) when is_binary(key) and byte_size(key) <= 100,
    do: Regex.match?(~r/^(blake3|sha256):[0-9a-f]{64}:[0-9]{1,20}$/, key)

  defp valid_key?(_), do: false
  defp valid_integer?(value), do: is_integer(value) and value >= 0 and value <= @maximum
  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp allowed?(map, keys),
    do: Enum.all?(Map.keys(map), &(&1 in keys or &1 in Enum.map(keys, fn key -> Atom.to_string(key) end)))

  defp normalize_row(row, keys), do: Map.new(Enum.filter(keys, &(not is_nil(value(row, &1)))), &{&1, value(row, &1)})
end
