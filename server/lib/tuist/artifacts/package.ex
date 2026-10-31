defmodule Tuist.Artifacts.Package do
  @moduledoc false
  alias Tuist.Storage

  @max_metadata_bytes 1_048_576
  @max_payload_bytes 21_474_836_480

  def valid_digest?(value), do: is_binary(value) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, value)

  def descriptor?(%{"digest" => digest, "size_bytes" => size, "media_type" => type} = descriptor) do
    map_size(descriptor) == 3 and valid_digest?(digest) and is_integer(size) and
      size >= 0 and size <= @max_payload_bytes and bounded_string?(type, 255)
  end

  def descriptor?(_), do: false

  def canonical(value) when is_map(value) do
    "{" <>
      (value |> Enum.sort() |> Enum.map_join(",", fn {key, value} -> JSON.encode!(key) <> ":" <> canonical(value) end)) <>
      "}"
  end

  def canonical(value) when is_list(value), do: "[" <> Enum.map_join(value, ",", &canonical/1) <> "]"
  def canonical(value), do: JSON.encode!(value)
  def digest(bytes), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  def key(intent), do: intent |> canonical() |> digest()

  def validate_intent(
        %{
          "schema" => "once.publication_intent.v1",
          "root" => root,
          "target" => target,
          "track" => track,
          "revision" => revision
        } = intent
      ) do
    if map_size(intent) == 5 and descriptor?(root) and bounded_string?(target, 1024) and
         optional_string?(track, 255) and optional_string?(revision, 128) do
      :ok
    else
      {:error, :invalid_intent}
    end
  end

  def validate_intent(_), do: {:error, :invalid_intent}

  defp bounded_string?(value, max),
    do: is_binary(value) and byte_size(value) in 1..max and not String.contains?(value, "\0")

  defp optional_string?(nil, _), do: true
  defp optional_string?(value, max), do: bounded_string?(value, max)

  def closure(project, key, root) do
    task = Task.async(fn -> read_closure(project, key, root) end)

    case Task.yield(task, 120_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :storage_unavailable}
    end
  end

  defp read_closure(project, key, root) do
    with {:ok, %{"schema" => "once.artifact_set.v1", "members" => members}} <- read_json(project, key, root),
         true <- is_map(members) and map_size(members) in 1..128 do
      Enum.reduce_while(members, {:ok, %{root["digest"] => root}}, fn {_name, member}, {:ok, contents} ->
        case add_member(contents, member, project, key) do
          {:ok, contents} -> {:cont, {:ok, contents}}
          error -> {:halt, error}
        end
      end)
    else
      {:error, :storage_unavailable} = error -> error
      _ -> {:error, :invalid_or_missing_content}
    end
  end

  defp add_member(contents, member, project, key) do
    with %{"artifact" => artifact} <- member,
         {:ok, %{"schema" => "once.artifact.v1", "payloads" => payloads, "interfaces" => interfaces}} <-
           read_json(project, key, artifact),
         true <- is_map(payloads) and map_size(payloads) in 1..128,
         true <- is_map(interfaces) and map_size(interfaces) <= 32,
         true <-
           Enum.all?(interfaces, fn {_id, interface} ->
             is_map(interface) and Map.has_key?(payloads, interface["payload"])
           end) do
      add_contents(contents, [artifact | Map.values(payloads)], project, key)
    else
      {:error, :storage_unavailable} = error -> error
      _ -> {:error, :invalid_or_missing_content}
    end
  end

  defp add_contents(contents, descriptors, project, key) do
    Enum.reduce_while(descriptors, {:ok, contents}, fn descriptor, {:ok, contents} ->
      with true <- descriptor?(descriptor),
           {:ok, size} <- object_size(project, key, descriptor),
           true <- size == descriptor["size_bytes"],
           updated = Map.put(contents, descriptor["digest"], descriptor),
           true <- Enum.sum(Enum.map(updated, fn {_, item} -> item["size_bytes"] end)) <= @max_payload_bytes do
        {:cont, {:ok, updated}}
      else
        {:error, :storage_unavailable} = error -> {:halt, error}
        _ -> {:halt, {:error, :invalid_or_missing_content}}
      end
    end)
  end

  def read_json(project, key, descriptor) do
    if descriptor?(descriptor) and descriptor["size_bytes"] <= @max_metadata_bytes do
      object_key = storage_key(project, key, descriptor["digest"])

      with {:ok, size} <- object_size(project, key, descriptor),
           true <- size == descriptor["size_bytes"] do
        read_verified_json(project, object_key, descriptor)
      else
        {:error, :storage_unavailable} = error -> error
        _ -> {:error, :invalid_or_missing_content}
      end
    else
      {:error, :invalid_descriptor}
    end
  end

  defp object_size(project, key, descriptor) do
    case Storage.get_object_size(storage_key(project, key, descriptor["digest"]), project.account) do
      {:ok, size} -> {:ok, size}
      {:error, :not_found} -> {:error, :invalid_or_missing_content}
      {:error, _} -> {:error, :storage_unavailable}
    end
  end

  defp read_verified_json(project, object_key, descriptor) do
    bytes =
      object_key
      |> Storage.stream_object(project.account)
      |> Enum.reduce_while("", fn chunk, bytes ->
        if byte_size(bytes) + byte_size(chunk) <= @max_metadata_bytes,
          do: {:cont, bytes <> chunk},
          else: {:halt, :too_large}
      end)

    with true <- is_binary(bytes) and byte_size(bytes) == descriptor["size_bytes"],
         true <- digest(bytes) == descriptor["digest"],
         {:ok, value} <- JSON.decode(bytes) do
      {:ok, value}
    else
      _ -> {:error, :invalid_content}
    end
  rescue
    _error in [ExAws.Error, RuntimeError] -> {:error, :storage_unavailable}
  end

  def storage_prefix(project, key), do: "#{project.account_id}/#{project.id}/artifacts/#{key}/"
  def storage_key(project, key, digest), do: storage_prefix(project, key) <> digest
end
