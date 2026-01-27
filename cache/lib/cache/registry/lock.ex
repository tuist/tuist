defmodule Cache.Registry.Lock do
  @moduledoc """
  Distributed lock backed by S3 objects for registry sync coordination.
  """

  alias Cache.Config

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
         |> ExAws.request() do
      {:ok, %{body: body, headers: headers}} ->
        with {:ok, lock} <- Jason.decode(body) do
          {:ok, lock, etag_from_headers(headers)}
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
    |> ExAws.request()
  end

  defp lock_key(:sync), do: "registry/locks/sync.json"

  defp lock_key({:package, scope, name}) do
    "registry/locks/packages/#{normalize_part(scope)}/#{normalize_part(name)}.json"
  end

  defp lock_key({:release, scope, name, version}) do
    "registry/locks/releases/#{normalize_part(scope)}/#{normalize_part(name)}/#{version}.json"
  end

  defp lock_key(other), do: "registry/locks/#{other}.json"

  defp bucket, do: Config.registry_bucket()

  defp etag_from_headers(headers) do
    etag_value = Map.get(headers, "etag") || Map.get(headers, "ETag")
    normalize_etag(etag_value)
  end

  defp normalize_etag(nil), do: nil
  defp normalize_etag([value | _]), do: normalize_etag(value)

  defp normalize_etag(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp if_match_value(etag) do
    if String.starts_with?(etag, "\"") do
      etag
    else
      "\"#{etag}\""
    end
  end

  defp normalize_part(value) do
    value
    |> String.downcase()
    |> String.replace(".", "_")
  end
end
