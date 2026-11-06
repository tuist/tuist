defmodule Pulse.ObjectStore do
  @moduledoc """
  Ergonomic wrapper around the `Pulse.ObjectStore.NIF` object store client.

  Every call takes an explicit `StoreConfig` map so the NIF has no ambient
  state.

  Beyond the plain `put/3`, `get/2`, `delete/2`, `list/2` operations this
  module also exposes the conditional variants Pulse's manifest CAS
  relies on: `put_if_none_match/3` for first-time creation,
  `put_if_match/4` for compare-and-swap updates, and `get_if_none_match/3`
  for cache-friendly conditional reads. Every write returns the new
  object's ETag so a caller does not have to issue a follow-up GET just
  to prime a CAS cache.
  """

  alias Pulse.ObjectStore.NIF

  @type config :: %{
          required(:bucket) => String.t(),
          required(:region) => String.t(),
          required(:access_key_id) => String.t(),
          required(:secret_access_key) => String.t(),
          required(:allow_http) => boolean(),
          optional(:endpoint) => String.t() | nil
        }

  @type etag :: String.t()

  @doc false
  def ensure_retention_api! do
    version =
      try do
        {NIF.retention_api_version(), NIF.keyed_publication_api_version(), NIF.snapshot_api_version(),
         NIF.async_api_version()}
      rescue
        ErlangError -> :unavailable
      end

    if version != {1, 1, 1, 1} do
      raise "object-store native artifact is incompatible with this Pulse release; rebuild with PULSE_NIF_FORCE_BUILD=1 or install the matching release artifacts"
    end

    :ok
  end

  @spec put(config(), String.t(), binary()) :: {:ok, etag()} | {:error, term()}
  def put(config, key, data) when is_map(config) and is_binary(key) and is_binary(data) do
    observe("put", key, byte_size(data), fn -> normalize(await(&NIF.put(&1, normalize_config(config), key, data))) end)
  end

  # Creates the object only if no object exists at that key (`If-None-Match: *`).
  # Returns `{:error, :already_exists}` if the key is already taken — the
  # loser in a first-create race retries by falling through to `put_if_match/4`
  # with the current ETag.
  @spec put_if_none_match(config(), String.t(), binary()) ::
          {:ok, etag()} | {:error, :already_exists | term()}
  def put_if_none_match(config, key, data) when is_map(config) and is_binary(key) and is_binary(data) do
    observe("put_if_none_match", key, byte_size(data), fn ->
      normalize(await(&NIF.put_if_none_match(&1, normalize_config(config), key, data)))
    end)
  end

  # Updates the object only if its current ETag matches (`If-Match: <etag>`).
  # Returns `{:error, :precondition_failed}` if the object changed since
  # the caller last read it — the standard CAS retry path.
  @spec put_if_match(config(), String.t(), binary(), etag()) ::
          {:ok, etag()} | {:error, :precondition_failed | :not_found | term()}
  def put_if_match(config, key, data, etag)
      when is_map(config) and is_binary(key) and is_binary(data) and is_binary(etag) do
    observe("put_if_match", key, byte_size(data), fn ->
      normalize(await(&NIF.put_if_match(&1, normalize_config(config), key, data, etag)))
    end)
  end

  @spec get(config(), String.t()) :: {:ok, binary()} | {:error, term()}
  def get(config, key) when is_map(config) and is_binary(key) do
    observe("get", key, 0, fn ->
      case await(&NIF.get(&1, normalize_config(config), key)) do
        {:ok, data} -> {:ok, data}
        other -> normalize(other)
      end
    end)
  end

  @doc "Verify exact existing object bytes by streaming, without allocating a second body binary."
  @spec verify(config(), String.t(), binary(), non_neg_integer()) :: :ok | {:error, term()}
  def verify(config, key, expected, timeout_ms \\ 15_000)
  def verify(_config, _key, _expected, 0), do: {:error, :timeout}

  def verify(config, key, expected, timeout_ms)
      when is_map(config) and is_binary(key) and is_binary(expected) and timeout_ms in 1..15_000 do
    # Measure a provider GET, including consumed bytes on a successful GET
    # whose content mismatches. This is not provider-billed wire accounting:
    # header rejection may consume no streamed body but still costs a GET.
    result =
      observe("get", key, 0, fn ->
        normalize(await(&NIF.verify(&1, normalize_config(config), key, expected, timeout_ms)))
      end)

    case result do
      {:ok, true, _read} -> :ok
      {:ok, false, _read} -> {:error, :keyed_content_mismatch}
      {:error, _} = error -> error
    end
  end

  # Conditional GET. `etag` may be `nil` (or `""`) to force a full read.
  #
  # - Object unchanged since `etag` was read → `:not_modified`. No body
  #   crosses the wire; parsing is skipped entirely.
  # - Object changed, or no ETag was supplied → `{:ok, new_etag, body}`.
  # - Missing key → `{:error, :not_found}`.
  @spec get_if_none_match(config(), String.t(), etag() | nil) ::
          {:ok, etag(), binary()} | :not_modified | {:error, :not_found | term()}
  def get_if_none_match(config, key, etag) when is_map(config) and is_binary(key) do
    etag_string = etag || ""

    observe("get_if_none_match", key, 0, fn ->
      case await(&NIF.get_if_none_match(&1, normalize_config(config), key, etag_string)) do
        {:ok, new_etag, data} -> {:ok, new_etag, data}
        other -> normalize(other)
      end
    end)
  end

  @doc "Conditional metadata GET with a native, pre-allocation body limit."
  def get_bounded(config, key, etag, limit) when is_integer(limit) and limit > 0 do
    observe("get_if_none_match", key, 0, fn ->
      normalize(await(&NIF.get_bounded(&1, normalize_config(config), key, etag || "", limit)))
    end)
  end

  @doc "Bounded strong-ETag snapshot GET; suffix zero reads the complete matching object."
  def get_snapshot(config, key, etag, suffix, limit, timeout_ms) do
    observe("get", key, 0, fn ->
      normalize(await(&NIF.get_snapshot(&1, normalize_config(config), key, etag || "", suffix, limit, timeout_ms)))
    end)
  end

  @doc "Bounded lexical listing; the returned start-after cursor survives deletion of earlier keys."
  def list_page(config, prefix, after_key \\ nil, limit \\ 512) when is_integer(limit) and limit in 1..1000 do
    if after_key != nil and not String.starts_with?(after_key, prefix) do
      {:error, :invalid_list_cursor}
    else
      observe("list", prefix, 0, fn ->
        normalize(await(&NIF.list_page(&1, normalize_config(config), prefix, after_key || "", limit)))
      end)
    end
  end

  @doc "Bounded tenant discovery that jumps over each ASCII managed subtree."
  def discover_tenants(config, after_tenant \\ nil, limit \\ 16) when limit in 1..64 do
    observe("list_prefixes", "tenants/", 0, fn ->
      normalize(await(&NIF.discover_tenants(&1, normalize_config(config), after_tenant || "", limit)))
    end)
  end

  @doc "Retention DELETE with four native in-flight slots that survive BEAM caller termination."
  def delete_bounded(config, key) do
    observe("delete", key, 0, fn -> normalize(await(&NIF.delete_bounded(&1, normalize_config(config), key))) end)
  end

  @spec delete(config(), String.t()) :: :ok | {:error, term()}
  def delete(config, key) when is_map(config) and is_binary(key) do
    observe("delete", key, 0, fn -> normalize(await(&NIF.delete(&1, normalize_config(config), key))) end)
  end

  @spec list(config(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list(config, prefix \\ "") when is_map(config) and is_binary(prefix) do
    observe("list", prefix, 0, fn ->
      case await(&NIF.list(&1, normalize_config(config), prefix)) do
        {:ok, keys} -> {:ok, keys}
        other -> normalize(other)
      end
    end)
  end

  @doc "List immediate directory prefixes, following provider pagination without materializing descendant object keys."
  @spec list_prefixes(config(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_prefixes(config, prefix) when is_map(config) and is_binary(prefix) do
    observe("list_prefixes", prefix, 0, fn ->
      normalize(await(&NIF.list_prefixes(&1, normalize_config(config), prefix)))
    end)
  end

  # Requests run on the native runtime, not on a BEAM scheduler: the NIF starts
  # one and returns `:ok`, then sends `{ref, result}` here when it completes.
  # The caller waits in an ordinary receive, so slow providers hold no dirty
  # scheduler. A fresh reference keeps the receive selective and O(1).
  defp await(start) do
    ref = make_ref()

    case start.(ref) do
      :ok ->
        receive do
          {^ref, result} -> result
        end

      {:error, _reason} = error ->
        error
    end
  end

  # Manifest pages are `.json` objects under `index/` (format 3) or
  # `journal/` (format 4); manifest backups live under `backups/`.
  defp purpose(key) do
    cond do
      String.ends_with?(key, "/manifest.json") -> "manifest"
      String.ends_with?(key, ".json") and String.contains?(key, ["/index/", "/journal/"]) -> "metadata_page"
      String.contains?(key, "/backups/") -> "backup"
      String.ends_with?(key, ".parquet") -> "segment"
      true -> "other"
    end
  end

  defp observe(operation, key, write_bytes, fun) do
    purpose = purpose(key)

    Pulse.Metrics.measure(
      :object,
      operation,
      fn -> request(String.to_existing_atom(operation), write_bytes, fun) end,
      fn
        {:ok, _etag, body} when is_binary(body) -> %{read: byte_size(body)}
        {:ok, body} when operation == "get" and is_binary(body) -> %{read: byte_size(body)}
        {:ok, matched?, bytes} when is_boolean(matched?) and is_integer(bytes) -> %{read: bytes}
        {:ok, _etag, _size, body} when is_binary(body) -> %{read: byte_size(body)}
        {:ok, _} when operation in ["put", "put_if_match", "put_if_none_match"] -> %{write: write_bytes}
        _ -> %{}
      end,
      purpose
    )
  end

  # Keep the canonical operation/payload counters alongside the detailed view;
  # the supplied native operation still runs exactly once.
  defp request(operation, write_bytes, fun) do
    Pulse.SelfMetrics.track(:object, operation, fn ->
      result = fun.()

      case {operation, result} do
        {:get, {:ok, data}} ->
          Pulse.SelfMetrics.object_bytes(:read, byte_size(data))

        {:get, {:ok, _etag, _size, body}} when is_binary(body) ->
          Pulse.SelfMetrics.object_bytes(:read, byte_size(body))

        {:get, {:ok, matched?, bytes}} when is_boolean(matched?) and is_integer(bytes) ->
          Pulse.SelfMetrics.object_bytes(:read, bytes)

        {:get_if_none_match, {:ok, _etag, data}} ->
          Pulse.SelfMetrics.object_bytes(:read, byte_size(data))

        {op, {:ok, _etag}} when op in [:put, :put_if_none_match, :put_if_match] ->
          Pulse.SelfMetrics.object_bytes(:write, write_bytes)

        _ ->
          :ok
      end

      result
    end)
  end

  # 304 responses reach us as a NIF error carrying the `:not_modified`
  # atom (that is what `Error::Term(Box::new(atoms::not_modified()))`
  # translates to on the BEAM side). We map it to a plain return value
  # so callers do not have to know the NIF error shape.
  defp normalize(:not_modified), do: :not_modified
  defp normalize(:ok), do: :ok
  defp normalize({:error, :not_modified}), do: :not_modified
  defp normalize({:error, reason}), do: {:error, reason}
  defp normalize(other), do: other

  defp normalize_config(config) do
    %{
      bucket: fetch!(config, :bucket),
      endpoint: Map.get(config, :endpoint),
      region: fetch!(config, :region),
      access_key_id: fetch!(config, :access_key_id),
      secret_access_key: fetch!(config, :secret_access_key),
      allow_http: Map.get(config, :allow_http, false)
    }
  end

  defp fetch!(config, key) do
    case Map.fetch(config, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Pulse.ObjectStore config is missing #{inspect(key)}"
    end
  end
end
