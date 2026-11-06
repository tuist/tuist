defmodule Pulse.Auth.IssuerCache do
  @moduledoc """
  Node-local cache of the trusted issuer's signing keys (JWKS) and signed
  status list.

  Every instance fetches independently on `refresh_interval_seconds`; the
  cache is a disposable optimization, never shared authority. Keys stay usable
  for `key_retention_seconds` after the last successful fetch, so an issuer
  outage does not stop ingestion; emergency key removal goes through the
  status list's `revoked_kids`, which applies within one refresh. A status
  list older than the one held is refused, so a replayed signed document
  cannot undo revocations.

  When `mirror` is enabled and Pulse uses object storage, each successful
  fetch is copied to `auth/issuer/` in the bucket. An instance that cannot
  reach the issuer (for example one started during an outage) loads keys and
  status from that mirror instead. Mirrored status lists are signed; mirrored
  keys are trusted like the rest of the bucket.

  Fetches run in a task, so callers asking for an on-demand refresh (an
  unknown `kid`) wait without blocking each other, and at most one fetch per
  30 seconds is triggered that way.
  """

  use GenServer

  alias Pulse.Auth.Issuer
  alias Pulse.Auth.Membership
  alias Pulse.Auth.Quota
  alias Pulse.Runtime
  alias Pulse.Storage.S3

  require Logger

  @jwks_key "auth/issuer/jwks.json"
  @status_key "auth/issuer/status.jwt"
  @members_prefix "auth/members/"
  @max_jwks_bytes 1_048_576
  @max_status_bytes 16_777_216
  @timeout_ms 5_000
  @min_refresh_ms 30_000

  def start_link(opts \\ []), do: Runtime.server_start(__MODULE__, opts, name: __MODULE__)

  @doc """
  Fresh keys and the current status list (nil when no status URL is
  configured), or `:unavailable` while keys are missing or stale, or a
  configured status list has never loaded.
  """
  def material do
    with ref when ref != :undefined <- :ets.whereis(Runtime.table(__MODULE__)),
         [{:config, config}] <- :ets.lookup(ref, :config),
         [{:keys, keys, fetched_at}] <- :ets.lookup(ref, :keys),
         true <- System.os_time(:second) - fetched_at <= config.key_retention_seconds do
      case :ets.lookup(ref, :status) do
        [{:status, status}] -> {:ok, keys, status}
        [] when is_nil(config.status_url) -> {:ok, keys, nil}
        [] -> :unavailable
      end
    else
      _ -> :unavailable
    end
  end

  @doc "Asks for a rate-limited refresh and waits for it to finish."
  def refresh do
    case Runtime.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.call(pid, :refresh, 3 * @timeout_ms)
    end
  catch
    :exit, _ -> :ok
  end

  @doc """
  Live Pulse instances sharing issuer configuration, used to divide tenant
  quotas: the larger of the clustered nodes and the instances with a fresh
  object-store heartbeat, so unclustered instances still divide quotas.
  """
  def members do
    scope = Runtime.name(Membership)

    clustered =
      if Process.whereis(scope),
        do: scope |> :pg.get_members(:issuer) |> Enum.map(&node/1) |> Enum.uniq() |> length(),
        else: 1

    heartbeats =
      with ref when ref != :undefined <- :ets.whereis(Runtime.table(__MODULE__)),
           [{:members, count}] <- :ets.lookup(ref, :members) do
        count
      else
        _ -> 1
      end

    Enum.max([clustered, heartbeats, 1])
  end

  @impl true
  def init(opts) do
    config = Keyword.get_lazy(opts, :config, &Issuer.config/0)
    table = :ets.new(Runtime.table(__MODULE__), [:named_table, :protected, read_concurrency: true])
    :ets.insert(table, {:config, config})
    :ets.new(Runtime.table(Quota), [:named_table, :public, write_concurrency: true])
    :ets.new(Runtime.table(Issuer), [:named_table, :public, read_concurrency: true, write_concurrency: true])

    scope = Runtime.name(Membership)
    if Process.whereis(scope), do: :pg.join(scope, :issuer, self())

    send(self(), :tick)

    {:ok,
     %{
       config: config,
       table: table,
       task: nil,
       waiters: [],
       last_attempt: nil,
       mirrored: %{jwks: nil, status: nil},
       instance: Base.encode16(:crypto.strong_rand_bytes(12), case: :lower),
       heartbeat: nil,
       http_options: Keyword.get(opts, :http_options, []),
       store: Keyword.get_lazy(opts, :object_store, fn -> default_store(config) end),
       store_config: Keyword.get_lazy(opts, :store_config, fn -> Map.new(Runtime.get_env(:pulse, S3, [])) end),
       min_refresh_ms: Keyword.get(opts, :min_refresh_ms, @min_refresh_ms)
     }}
  end

  defp default_store(_config) do
    adapter = Keyword.get(Runtime.get_env(:pulse, Pulse.Storage, []), :adapter)
    if adapter == S3, do: Pulse.ObjectStore
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, state.config.refresh_interval_seconds * 1000)
    Quota.prune()
    Issuer.prune_claims()
    {:noreply, start(state)}
  end

  def handle_info({ref, result}, %{task: ref} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, state |> apply_result(result) |> reply_waiters()}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: ref} = state) do
    Logger.warning("issuer key refresh crashed: #{inspect(reason)}")
    {:noreply, reply_waiters(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:refresh, from, %{task: nil} = state) do
    if state.last_attempt && System.monotonic_time(:millisecond) - state.last_attempt < state.min_refresh_ms,
      do: {:reply, :ok, state},
      else: {:noreply, %{start(state) | waiters: [from | state.waiters]}}
  end

  def handle_call(:refresh, from, state), do: {:noreply, %{state | waiters: [from | state.waiters]}}

  defp start(%{task: nil} = state) do
    snapshot = %{
      config: state.config,
      keys: current(state.table, :keys),
      status: current(state.table, :status),
      mirrored: state.mirrored,
      http_options: state.http_options,
      store: state.store,
      store_config: state.store_config,
      instance: state.instance,
      heartbeat: state.heartbeat
    }

    task = Task.async(Runtime.capture(fn -> fetch(snapshot) end))
    %{state | task: task.ref, last_attempt: System.monotonic_time(:millisecond)}
  end

  defp start(state), do: state

  defp current(table, :keys) do
    case :ets.lookup(table, :keys) do
      [{:keys, keys, fetched_at}] -> {keys, fetched_at}
      [] -> nil
    end
  end

  defp current(table, :status) do
    case :ets.lookup(table, :status) do
      [{:status, status}] -> status
      [] -> nil
    end
  end

  defp reply_waiters(state) do
    for from <- state.waiters, do: GenServer.reply(from, :ok)
    %{state | task: nil, waiters: []}
  end

  defp apply_result(state, %{keys: keys, status: status, mirrored: mirrored, members: members}) do
    with {list, fetched_at} <- keys, do: :ets.insert(state.table, {:keys, list, fetched_at})
    if status, do: :ets.insert(state.table, {:status, status})

    case members do
      {count, heartbeat} ->
        :ets.insert(state.table, {:members, count})
        %{state | mirrored: mirrored, heartbeat: heartbeat}

      nil ->
        %{state | mirrored: mirrored}
    end
  end

  # Runs in a task: fetch keys, then the status list they verify, falling back
  # to the object-store mirror when the issuer cannot be reached and nothing
  # newer is held.
  defp fetch(snapshot) do
    %{config: config} = snapshot
    now = System.os_time(:second)

    {keys, jwks_body} =
      case get(config.jwks_url, config, @max_jwks_bytes, snapshot.http_options) do
        {:ok, body} ->
          case Issuer.parse_jwks(body) do
            {:ok, keys} -> {{keys, now}, body}
            {:error, reason} -> {fallback_keys(snapshot, {:invalid_jwks, reason}), nil}
          end

        {:error, reason} ->
          {fallback_keys(snapshot, reason), nil}
      end

    verify_keys = elem(keys || snapshot.keys || {[], 0}, 0)
    {status, status_jwt} = fetch_status(snapshot, verify_keys)

    mirrored =
      snapshot.mirrored
      |> mirror_jwks(snapshot, jwks_body, now)
      |> mirror_status(snapshot, status, status_jwt)

    %{keys: keys, status: status, mirrored: mirrored, members: heartbeat(snapshot, status || snapshot.status, now)}
  end

  # Quota membership without clustering: each instance writes an empty
  # `auth/members/<instance>/<unix seconds>` object every refresh and counts
  # instances whose latest heartbeat is within three intervals. Instances
  # remove their previous heartbeat and, a bounded number per pass, heartbeats
  # left by instances gone for ten intervals. Runs only while the status list
  # publishes quotas, so deployments without quotas make no requests.
  defp heartbeat(%{store: nil}, _status, _now), do: nil
  defp heartbeat(_snapshot, status, _now) when not is_map(status) or map_size(status.quotas) == 0, do: nil

  defp heartbeat(snapshot, _status, now) do
    %{store: store, store_config: config, instance: instance} = snapshot
    interval = snapshot.config.refresh_interval_seconds
    key = "#{@members_prefix}#{instance}/#{now}"

    with {:ok, _} <- store.put(config, key, ""),
         {:ok, keys} <- store.list(config, @members_prefix) do
      if snapshot.heartbeat && snapshot.heartbeat != key, do: store.delete(config, snapshot.heartbeat)

      beats = for raw <- keys, {:ok, owner, at} <- [parse_heartbeat(raw)], do: {raw, owner, at}

      latest =
        Enum.reduce(beats, %{}, fn {_raw, owner, at}, acc -> Map.update(acc, owner, at, &max(&1, at)) end)

      beats
      |> Enum.filter(fn {raw, _owner, at} -> at < now - 10 * interval and raw != key end)
      |> Enum.take(100)
      |> Enum.each(fn {raw, _owner, _at} -> store.delete(config, raw) end)

      fresh = Enum.count(latest, fn {_owner, at} -> at >= now - 3 * interval end)
      {max(fresh, 1), key}
    else
      {:error, reason} ->
        Logger.warning("issuer quota heartbeat failed: #{inspect(reason)}")
        nil
    end
  end

  defp parse_heartbeat(@members_prefix <> rest) do
    with [owner, at] <- String.split(rest, "/"),
         {at, ""} <- Integer.parse(at),
         do: {:ok, owner, at},
         else: (_ -> :error)
  end

  defp parse_heartbeat(_key), do: :error

  defp fallback_keys(snapshot, reason) do
    Logger.warning("issuer JWKS refresh failed: #{inspect(reason)}")

    with nil <- snapshot.keys,
         {:ok, body} <- mirror_get(snapshot, @jwks_key),
         {:ok, %{"fetched_at" => at, "jwks" => jwks}} when is_integer(at) <- JSON.decode(body),
         {:ok, keys} <- Issuer.parse_jwks(JSON.encode!(jwks)) do
      Logger.info("issuer JWKS loaded from the object-store mirror")
      {keys, at}
    else
      _ -> nil
    end
  end

  defp fetch_status(%{config: %{status_url: nil}}, _keys), do: {nil, nil}

  defp fetch_status(snapshot, keys) do
    %{config: config, status: current} = snapshot

    result =
      with {:ok, jwt} <- get(config.status_url, config, @max_status_bytes, snapshot.http_options),
           {:ok, status} <- Issuer.parse_status(jwt, keys, current, config),
           do: {:ok, status, jwt}

    case result do
      {:ok, %{version: version}, _jwt} when current != nil and version == current.version ->
        {nil, nil}

      {:ok, status, jwt} ->
        {status, jwt}

      {:error, reason} ->
        Logger.warning("issuer status list refresh failed: #{inspect(reason)}")

        with nil <- current,
             {:ok, jwt} <- mirror_get(snapshot, @status_key),
             {:ok, status} <- Issuer.parse_status(jwt, keys, nil, config) do
          Logger.info("issuer status list loaded from the object-store mirror")
          {status, nil}
        else
          _ -> {nil, nil}
        end
    end
  end

  defp mirror_get(%{store: nil}, _key), do: :error
  defp mirror_get(%{config: %{mirror: false}}, _key), do: :error
  defp mirror_get(%{store: store, store_config: config}, key), do: store.get(config, key)

  defp mirror_jwks(mirrored, %{store: nil}, _body, _now), do: mirrored
  defp mirror_jwks(mirrored, %{config: %{mirror: false}}, _body, _now), do: mirrored
  defp mirror_jwks(mirrored, _snapshot, nil, _now), do: mirrored

  defp mirror_jwks(mirrored, snapshot, body, now) do
    digest = :crypto.hash(:sha256, body)

    if digest == mirrored.jwks do
      mirrored
    else
      document = JSON.encode!(%{"fetched_at" => now, "jwks" => JSON.decode!(body)})

      case snapshot.store.put(snapshot.store_config, @jwks_key, document) do
        {:ok, _} -> %{mirrored | jwks: digest}
        {:error, reason} -> mirror_failed(mirrored, reason)
      end
    end
  end

  defp mirror_status(mirrored, %{store: nil}, _status, _jwt), do: mirrored
  defp mirror_status(mirrored, %{config: %{mirror: false}}, _status, _jwt), do: mirrored
  defp mirror_status(mirrored, _snapshot, _status, nil), do: mirrored

  defp mirror_status(mirrored, snapshot, %{version: version}, jwt) do
    if mirrored.status && mirrored.status >= version do
      mirrored
    else
      case snapshot.store.put(snapshot.store_config, @status_key, jwt) do
        {:ok, _} -> %{mirrored | status: version}
        {:error, reason} -> mirror_failed(mirrored, reason)
      end
    end
  end

  defp mirror_failed(mirrored, reason) do
    Logger.warning("issuer mirror write failed: #{inspect(reason)}")
    mirrored
  end

  defp get(url, config, max_bytes, http_options) do
    tls = if config.ca_file, do: [cacertfile: config.ca_file], else: []

    options =
      Keyword.merge(
        [
          url: url,
          retry: false,
          redirect: false,
          decode_body: false,
          receive_timeout: @timeout_ms,
          connect_options: [timeout: @timeout_ms, transport_opts: tls],
          into: fn {:data, data}, {request, response} ->
            body = response.body <> data

            if byte_size(body) > max_bytes,
              do: {:halt, {request, %{response | body: :too_large}}},
              else: {:cont, {request, %{response | body: body}}}
          end
        ],
        http_options
      )

    case Req.get(options) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200}} -> {:error, :response_too_large}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, exception} -> {:error, {:request_failed, Exception.message(exception)}}
    end
  end
end
