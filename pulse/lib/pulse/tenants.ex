defmodule Pulse.Tenants do
  @moduledoc """
  Tenant registry: lifecycle state and credentials for tenants provisioned
  through the admin API, stored in object storage so every instance agrees.

  Each tenant has one record, `system/tenants/v1/<tenant>.json`:

      {"tenant": "acme", "state": "active", "token_hashes": ["sha256$<hex>"],
       "created_at": ms, "updated_at": ms}

  States are `active`, `suspended` (requests refused with 403, data kept),
  `deleting` (refused; a purge is scheduled) and `deleted` (purged; the name
  stays reserved forever, so caches on other instances can never mix a new
  tenant with the old one's data). Records change only through conditional
  writes. Tenants without a record are unaffected: they keep authenticating
  with `PULSE_TENANT_TOKENS` as before.

  Instances cache records node-locally for `:cache_ttl_ms`, so a suspension or
  deletion takes effect everywhere within that time. Cache misses read the
  record from storage at most `:max_lookups_per_second` times per instance;
  above that, unknown tenants get a retryable `:auth_unavailable`, so requests
  naming random tenants cannot turn into unbounded storage reads. The cache is
  disposable and bounded.

  Deletion writes a marker under `system/tenant-deletions/v1/`;
  `Pulse.Tenants.Purger` deletes the tenant's `tenants/<tenant>/` objects once
  `:deletion_grace_ms` has passed, long enough for every instance's cache to
  refuse the tenant and in-flight work to finish.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.ObjectStore
  alias Pulse.Runtime
  alias Pulse.Runtime.GenServer
  alias Pulse.Storage.S3

  @cache __MODULE__
  @max_cache 100_000
  @max_token_hashes 8
  @attempts 8
  @writable_states ~w(active suspended)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def key(tenant), do: "system/tenants/v1/#{tenant}.json"
  def deletion_key(tenant), do: "system/tenant-deletions/v1/#{tenant}"
  def deletion_prefix, do: "system/tenant-deletions/v1/"

  defp cache, do: Runtime.table(@cache)
  def config(key, default), do: Keyword.get(Runtime.get_env(:pulse, __MODULE__, []), key, default)

  @doc "Whether the registry is enabled on this instance."
  def enabled?, do: config(:enabled, false)

  @impl true
  def init(_opts) do
    :ets.new(cache(), [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
    {:ok, nil}
  end

  @doc """
  Whether requests for `tenant` may proceed: tenants without a record, or with
  an active one, may. Called after credentials verify.
  """
  @spec check(String.t()) :: :ok | {:error, :forbidden | :auth_unavailable}
  def check(tenant) do
    if enabled?() do
      case lookup(tenant) do
        {:ok, nil} -> :ok
        {:ok, %{"state" => "active"}} -> :ok
        {:ok, _record} -> {:error, :forbidden}
        {:error, _} -> {:error, :auth_unavailable}
      end
    else
      :ok
    end
  end

  @doc """
  Whether background work (compaction, retention, alerting) should run for
  `tenant`. Unknown and unreadable tenants count as active: an unreadable
  registry must not stop maintenance, and purges re-list until empty.
  """
  def active?(tenant), do: check(tenant) != {:error, :forbidden}

  @doc """
  Token hashes (`sha256$<hex>`) of a registered tenant, whatever its state:
  a valid credential for a suspended or deleted tenant then fails `check/1`
  with 403 rather than looking unknown.
  """
  @spec token_hashes(String.t()) :: {:ok, [String.t()]} | {:error, :auth_unavailable}
  def token_hashes(tenant) do
    if enabled?() do
      case lookup(tenant) do
        {:ok, %{"token_hashes" => hashes}} when is_list(hashes) -> {:ok, hashes}
        {:ok, _} -> {:ok, []}
        {:error, _} -> {:error, :auth_unavailable}
      end
    else
      {:ok, []}
    end
  end

  # Fresh cache entries answer directly. Misses and expired entries read the
  # record within the lookup budget; an expired entry is served stale when
  # the budget is spent.
  defp lookup(tenant) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(cache(), tenant) do
      [{_, record, expires}] when expires > now -> {:ok, record}
      cached -> refresh(tenant, cached, now)
    end
  rescue
    ArgumentError -> {:error, :registry_unavailable}
  end

  defp refresh(tenant, cached, now) do
    with :ok <- take_lookup(now),
         {:ok, record, _etag} <- read(tenant) do
      remember(tenant, record, now)
      {:ok, record}
    else
      {:error, _} = error ->
        case cached do
          [{_, record, _expired}] -> {:ok, record}
          [] -> error
        end
    end
  end

  defp remember(tenant, record, now) do
    table = cache()

    if :ets.info(table, :size) >= @max_cache do
      :ets.select_delete(table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
      if :ets.info(table, :size) >= @max_cache, do: :ets.delete_all_objects(table)
    end

    :ets.insert(table, {tenant, record, now + config(:cache_ttl_ms, 30_000)})
  end

  # A one-second fixed window per instance; the row is `{:lookups, second, count}`.
  defp take_lookup(now) do
    second = div(now, 1000)
    key = :lookups
    table = cache()

    count =
      case :ets.lookup(table, key) do
        [{_, ^second, _}] ->
          :ets.update_counter(table, key, {3, 1})

        _ ->
          :ets.insert(table, {key, second, 1})
          1
      end

    if count <= config(:max_lookups_per_second, 100), do: :ok, else: {:error, :registry_busy}
  end

  @doc "Forget the cached record of `tenant` on this instance."
  def invalidate(tenant) do
    :ets.delete(cache(), tenant)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Read a record straight from storage: `{:ok, record | nil, etag | nil}`."
  def read(tenant) do
    with {:ok, storage} <- storage() do
      case ObjectStore.get_if_none_match(storage, key(tenant), nil) do
        {:ok, etag, body} ->
          decode(body, etag)

        {:error, :not_found} ->
          {:ok, nil, nil}

        {:error, _} = error ->
          error
      end
    end
  end

  defp decode(body, etag) do
    case Pulse.JSON.decode(body) do
      {:ok, %{"state" => _} = record} -> {:ok, record, etag}
      _ -> {:error, :tenant_record_invalid}
    end
  end

  @doc """
  Create or update `tenant` with `attrs` (`state`: `active` or `suspended`,
  and `token_hashes`). Deleting or deleted tenants cannot be changed.
  """
  def put(tenant, attrs) do
    with {:ok, changes} <- validate(attrs) do
      update(tenant, fn
        %{"state" => state} when state in ["deleting", "deleted"] ->
          {:error, :tenant_deleted}

        current ->
          base = %{"tenant" => tenant, "created_at" => now_ms(), "state" => "active", "token_hashes" => []}
          {:ok, Map.merge(current || base, changes)}
      end)
    end
  end

  @doc """
  Start deleting `tenant`: every instance refuses it within the cache TTL and
  a purge of its data is scheduled. Idempotent; a tenant without a record
  (for example, one authenticated by `PULSE_TENANT_TOKENS`) gets a tombstone.
  """
  def delete(tenant) do
    result =
      update(tenant, fn
        %{"state" => state} = current when state in ["deleting", "deleted"] ->
          {:ok, current}

        current ->
          record = current || %{"tenant" => tenant, "created_at" => now_ms(), "token_hashes" => []}
          {:ok, Map.merge(record, %{"state" => "deleting", "deletion_requested_at" => now_ms()})}
      end)

    with {:ok, %{"state" => "deleting"} = record} <- result,
         {:ok, storage} <- storage(),
         {:ok, _} <- ObjectStore.put(storage, deletion_key(tenant), Pulse.JSON.encode!(%{"tenant" => tenant})) do
      {:ok, record}
    end
  end

  @doc "Mark a purged tenant as deleted and remove its deletion marker."
  def finish_deletion(tenant) do
    with {:ok, _record} <-
           update(tenant, fn
             %{"state" => "deleting"} = current ->
               {:ok, Map.merge(current, %{"state" => "deleted", "deleted_at" => now_ms()})}

             current ->
               {:ok, current}
           end),
         {:ok, storage} <- storage() do
      ObjectStore.delete(storage, deletion_key(tenant))
    end
  end

  defp update(tenant, fun, attempts \\ @attempts)
  defp update(_tenant, _fun, 0), do: {:error, :tenant_conflict}

  defp update(tenant, fun, attempts) do
    with {:ok, storage} <- storage(),
         {:ok, current, etag} <- read(tenant),
         {:ok, record} <- fun.(current) do
      if record == current,
        do: {:ok, record},
        else: commit(storage, tenant, Map.put(record, "updated_at", now_ms()), etag, fun, attempts)
    end
  end

  defp commit(storage, tenant, record, etag, fun, attempts) do
    case write(storage, tenant, record, etag) do
      {:ok, _etag} -> {:ok, record}
      {:error, reason} when reason in [:precondition_failed, :already_exists] -> update(tenant, fun, attempts - 1)
      {:error, _} = error -> error
    end
  end

  # Conditional on the version read; the local cache is dropped either way.
  defp write(storage, tenant, record, etag) do
    body = Pulse.JSON.encode!(record)

    written =
      if etag,
        do: ObjectStore.put_if_match(storage, key(tenant), body, etag),
        else: ObjectStore.put_if_none_match(storage, key(tenant), body)

    invalidate(tenant)
    written
  end

  @doc "One page of registered tenant names, in lexical order, and the next cursor."
  def list(after_tenant, limit) when limit in 1..1000 do
    prefix = "system/tenants/v1/"

    with {:ok, storage} <- storage(),
         {:ok, keys, cursor} <- ObjectStore.list_page(storage, prefix, after_tenant && key(after_tenant), limit) do
      names = Enum.map(keys, &(&1 |> String.replace_prefix(prefix, "") |> String.replace_suffix(".json", "")))
      {:ok, names, cursor && List.last(names)}
    end
  end

  defp validate(attrs) when is_map(attrs) do
    allowed = Map.take(attrs, ["state", "token_hashes"])

    cond do
      map_size(allowed) != map_size(attrs) ->
        {:error, {:invalid_request, "only state and token_hashes may be set"}}

      Map.has_key?(attrs, "state") and attrs["state"] not in @writable_states ->
        {:error, {:invalid_request, "state must be active or suspended; use DELETE to delete"}}

      Map.has_key?(attrs, "token_hashes") and not valid_hashes?(attrs["token_hashes"]) ->
        {:error, {:invalid_request, "token_hashes must be at most #{@max_token_hashes} sha256$<64 hex> values"}}

      true ->
        {:ok, allowed}
    end
  end

  defp validate(_attrs), do: {:error, {:invalid_request, "body must be a JSON object"}}

  defp valid_hashes?(hashes) when is_list(hashes) and length(hashes) <= @max_token_hashes,
    do: Enum.all?(hashes, &(is_binary(&1) and Regex.match?(~r/\Asha256\$[0-9a-f]{64}\z/, &1)))

  defp valid_hashes?(_), do: false

  @doc false
  def storage do
    case Runtime.get_env(:pulse, S3) do
      nil -> {:error, :registry_storage_unavailable}
      config -> {:ok, Map.new(config)}
    end
  end

  defp now_ms, do: System.os_time(:millisecond)
end
