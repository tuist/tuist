defmodule Cache.Registry.Lock do
  @moduledoc """
  Distributed lock backed by S3 objects for registry sync coordination.
  """

  require Logger

  @spec try_acquire(term(), pos_integer()) :: {:ok, :acquired} | {:error, :already_locked}
  def try_acquire(key, ttl_seconds) when is_integer(ttl_seconds) and ttl_seconds > 0 do
    lock_key = lock_key(key)
    now = System.system_time(:second)
    expires_at = now + ttl_seconds
    body = Jason.encode!(%{acquired_at: now, expires_at: expires_at, node: node() |> to_string()})

    case read_lock(lock_key) do
      {:ok, %{"expires_at" => expires_at}} when is_integer(expires_at) and expires_at > now ->
        {:error, :already_locked}

      _ ->
        case put_lock(lock_key, body) do
          {:ok, _} -> {:ok, :acquired}
          {:error, reason} ->
            Logger.warning("Failed to acquire registry lock #{lock_key}: #{inspect(reason)}")
            {:error, :already_locked}
        end
    end
  end

  def release(key) do
    lock_key = lock_key(key)
    bucket = bucket()

    _ =
      bucket
      |> ExAws.S3.delete_object(lock_key)
      |> ExAws.request()

    :ok
  end

  defp read_lock(lock_key) do
    bucket = bucket()

    case bucket
         |> ExAws.S3.get_object(lock_key)
         |> ExAws.request() do
      {:ok, %{body: body}} -> Jason.decode(body)
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_lock(lock_key, body, opts) do
    bucket = bucket()

    bucket
    |> ExAws.S3.put_object(lock_key, body, Keyword.merge([content_type: "application/json"], opts))
    |> ExAws.request()
  end

  defp put_lock(lock_key, body), do: put_lock(lock_key, body, [])

  defp lock_key(:sync), do: "registry/locks/sync.json"

  defp lock_key({:package, scope, name}) do
    "registry/locks/packages/#{normalize_part(scope)}/#{normalize_part(name)}.json"
  end

  defp lock_key({:release, scope, name, version}) do
    "registry/locks/releases/#{normalize_part(scope)}/#{normalize_part(name)}/#{version}.json"
  end

  defp lock_key(other), do: "registry/locks/#{other}.json"

  defp bucket, do: Application.get_env(:cache, :s3)[:bucket]

  defp normalize_part(value) do
    value
    |> String.downcase()
    |> String.replace(".", "_")
  end
end
