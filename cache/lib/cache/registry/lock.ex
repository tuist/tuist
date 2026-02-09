defmodule Cache.Registry.Lock do
  @moduledoc """
  Distributed lock backed by S3 objects for registry sync coordination.
  """

  alias Cache.Config
  alias Cache.Registry.KeyNormalizer
  alias Cache.S3

  require Logger

  def try_acquire(key, ttl_seconds) when is_integer(ttl_seconds) and ttl_seconds > 0 do
    lock_key = lock_key(key)
    now = System.system_time(:second)
    expires_at = now + ttl_seconds
    body = Jason.encode!(%{acquired_at: now, expires_at: expires_at, node: to_string(node())})

    case put_lock(lock_key, body, if_none_match: "*") do
      {:ok, _} ->
        {:ok, :acquired}

      {:error, {:http_error, 412, _}} ->
        maybe_replace_expired(lock_key, body, now)

      {:error, reason} ->
        Logger.warning("Failed to acquire registry lock #{lock_key}: #{inspect(reason)}")
        {:error, :already_locked}
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

  defp maybe_replace_expired(lock_key, body, now) do
    case read_lock(lock_key) do
      {:ok, %{"expires_at" => expires_at}, etag}
      when is_integer(expires_at) and expires_at <= now and is_binary(etag) ->
        try_replace_with_etag(lock_key, body, etag)

      {:error, :not_found} ->
        try_create_lock(lock_key, body)

      {:ok, _lock, _etag} ->
        {:error, :already_locked}

      _ ->
        {:error, :already_locked}
    end
  end

  defp try_replace_with_etag(lock_key, body, etag) do
    case put_lock(lock_key, body, if_match: if_match_value(etag)) do
      {:ok, _} -> {:ok, :acquired}
      {:error, _reason} -> {:error, :already_locked}
    end
  end

  defp try_create_lock(lock_key, body) do
    case put_lock(lock_key, body, if_none_match: "*") do
      {:ok, _} -> {:ok, :acquired}
      {:error, _reason} -> {:error, :already_locked}
    end
  end

  defp read_lock(lock_key) do
    bucket = bucket()

    case bucket
         |> ExAws.S3.get_object(lock_key)
         |> with_tigris_consistency()
         |> ExAws.request() do
      {:ok, %{body: body, headers: headers}} ->
        with {:ok, lock} <- Jason.decode(body) do
          {:ok, lock, S3.etag_from_headers(headers)}
        end

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp put_lock(lock_key, body, opts) do
    bucket = bucket()

    bucket
    |> ExAws.S3.put_object(lock_key, body, Keyword.merge([content_type: "application/json"], opts))
    |> with_tigris_consistency()
    |> ExAws.request()
  end

  defp with_tigris_consistency(%{headers: headers} = op) do
    %{op | headers: Map.put(headers, "X-Tigris-Consistent", "true")}
  end

  defp lock_key(:sync), do: "registry/locks/sync.json"

  defp lock_key({:package, scope, name}) do
    "registry/locks/packages/#{KeyNormalizer.normalize_scope(scope)}/#{KeyNormalizer.normalize_name(name)}.json"
  end

  defp lock_key({:release, scope, name, version}) do
    "registry/locks/releases/#{KeyNormalizer.normalize_scope(scope)}/#{KeyNormalizer.normalize_name(name)}/#{version}.json"
  end

  defp lock_key(other), do: "registry/locks/#{other}.json"

  defp bucket, do: Config.registry_bucket()

  defp if_match_value(etag) do
    if String.starts_with?(etag, "\"") do
      etag
    else
      "\"#{etag}\""
    end
  end
end
