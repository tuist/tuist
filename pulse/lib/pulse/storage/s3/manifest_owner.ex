defmodule Pulse.Storage.S3.ManifestOwner do
  @moduledoc """
  Per-`(tenant, signal)` manifest writer.

  Every S3 CAS on a manifest funnels through one owner process — so
  there is no local write contention on that manifest object, and the
  S3 conditional PUT only ever fights genuine cross-node races (not
  in-process ones).

  ## Write coalescing

  Multiple ingester calls that arrive close together are batched into
  one CAS. Each caller enqueues its segment(s) and blocks in
  `GenServer.call/3`; the owner accumulates a pending list, starts a
  short flush timer (default 10ms), and on flush issues **one** CAS
  that folds every pending segment into the manifest. Every waiter is
  replied to once the CAS lands.

  Under steady write load this pins the S3 CAS rate to
  `1 / flush_interval_ms` per tenant regardless of how many concurrent
  ingesters push. Under bursty load the batch cap (default 256) triggers
  an immediate flush without waiting for the timer, so tail latency
  stays bounded.

  With `:ingest_flush_interval_ms` set, publications also start at most once
  per that interval: a registration arriving sooner after the previous
  publication started waits for the rest of the interval and shares the next
  CAS. Every root write is a billed PUT, so this bounds an owner's root writes
  to one per interval however many requests (keyed, unbuffered or coalesced)
  arrive. Acknowledgments still wait for that CAS.

  ## Conflict recovery

  On a `:precondition_failed` from S3 (another node landed a CAS on the
  same manifest between our GET and PUT), the owner reloads the
  manifest, re-applies its pending segments on top, and retries. Retries
  are bounded and back off before giving up.

  ## First-write migration

  When the owner boots and no manifest exists yet at that key, it
  rebuilds one by LIST-ing the tenant's segment prefix — every
  historical write from before the manifest existed still ends up in
  the manifest on first read.

  ## Backpressure

  Every `register_segments` call checks the owner's mailbox length
  (`Process.info(pid, :message_queue_len)`) before it hands off and
  short-circuits with `{:error, :owner_overloaded}` when we're already
  at or above `max_mailbox` (default 512). This is the explicit
  backpressure signal to the ingester layer above — callers see a
  typed error and can shed load rather than sitting on a 15s
  `GenServer.call` timeout while the mailbox keeps growing. And on
  the timeout path, `call_owner/3` translates
  `exit({:timeout, {GenServer, :call, _}})` into
  `{:error, :timeout}`, so `register_segments/5` honors the typed
  return in its `@spec` in every failure mode. The mailbox-length
  probe is inherently racy (the length may rise between check and
  enqueue), but the race is bounded by the number of concurrent
  callers — not unbounded as the earlier design allowed.
  """

  use Pulse.Runtime.GenServer, restart: :transient

  alias Pulse.ObjectStore
  alias Pulse.Runtime.GenServer
  alias Pulse.Runtime.Registry
  alias Pulse.Storage.S3.JournalManifest
  alias Pulse.Storage.S3.Manifest
  alias Pulse.Storage.S3.Manifest.Segment
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.ManifestRegistry
  alias Pulse.Storage.S3.ManifestSupervisor
  alias Pulse.Storage.S3.PagedManifest
  alias Pulse.Storage.S3.Retention

  require Logger

  @registry ManifestRegistry
  @default_flush_interval_ms 10
  @default_flush_batch_max 256
  @cas_max_retries 5
  @published_payload {__MODULE__, :published_payload}
  @wire_cache {__MODULE__, :wire_cache}
  @published_bytes {__MODULE__, :published_bytes}
  # A cached manifest is served without I/O for this long after its
  # last refresh; beyond it, `ensure_loaded/3` issues a conditional GET
  # to pick up cross-node writes. This is the bound on cross-node
  # freshness in the absence of UDP gossip.
  @default_refresh_stale_ms 1_000
  # Ceiling on the owner's mailbox length. Every `register_segments`
  # call checks the owner's `:message_queue_len` before it hands off
  # and short-circuits with `{:error, :owner_overloaded}` when we're
  # already at or above the ceiling. This is the explicit backpressure
  # signal — callers see a typed error and can shed load rather than
  # sitting on a 15s timeout while the mailbox keeps growing. The
  # check is racy (mailbox length can rise between check and call),
  # but the race is bounded: at worst we overshoot by the number of
  # racing callers, which is `O(ingester concurrency)`, not unbounded.
  @default_max_mailbox 512

  # Idle owners hibernate after this many milliseconds. `:hibernate` GCs
  # the heap and drops any large stack — the owner will still respond to
  # the next call, just after a small wakeup cost. This keeps the
  # per-tenant memory footprint bounded when a tenant goes quiet.
  @idle_hibernate_ms 30_000

  @type opts :: [
          tenant: String.t(),
          signal: String.t(),
          config: map(),
          flush_interval_ms: pos_integer(),
          flush_batch_max: pos_integer()
        ]

  # ---- public API -----------------------------------------------------------

  @doc """
  Register segments in the manifest and wait until the CAS lands.

  Returns `:ok` once the manifest that references every supplied
  segment is durably in S3, `{:error, reason}` otherwise.

  ## Typed error contract

  This function only ever returns `:ok | {:error, term()}`; the
  underlying `GenServer.call/3`'s `exit({:timeout, _})` on call
  timeout is translated to `{:error, :timeout}`, and a mailbox
  saturation to `{:error, :owner_overloaded}`, so the caller can
  shed load without a `try/catch`.
  """
  @spec register_segments(String.t(), String.t(), [Segment.t()], map(), timeout()) ::
          :ok | {:error, term()}
  def register_segments(tenant, signal, segments, config, timeout \\ 15_000)
      when is_binary(tenant) and is_binary(signal) and is_list(segments) and is_map(config) do
    with {:ok, pid} <- ensure_started(tenant, signal, config),
         :ok <- guard_mailbox(pid, config) do
      # The send time lets the owner report mailbox wait as manifest_wait.
      call_owner(pid, {:register_segments, segments, System.monotonic_time()}, timeout)
    end
  end

  # `Process.info(pid, :message_queue_len)` is cheap (one BIF, no
  # message crossing). We use it as an in-flight cap so an ingester
  # burst that has overwhelmed the owner shows up as a typed error
  # to the caller, not as unbounded mailbox growth followed by a 15s
  # `GenServer.call` timeout. The check is racy (the length may rise
  # between check and enqueue), but the race is bounded by the
  # number of concurrent callers — far short of the "unbounded" the
  # earlier design allowed.
  defp guard_mailbox(pid, config) do
    ceiling = Map.get(config, :max_mailbox, @default_max_mailbox)

    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} when len >= ceiling ->
        {:error, :owner_overloaded}

      _ ->
        :ok
    end
  end

  # Translate the `GenServer.call/3` timeout `exit` into a typed
  # error tuple so callers can pattern-match on it — a `catch` on
  # every call site would be worse. Any other exit is re-raised
  # because it signals a genuine bug (owner crashed, unknown
  # message shape, etc.) and callers should not swallow it.
  defp call_owner(pid, request, timeout) do
    GenServer.call(pid, request, timeout)
  catch
    :exit, {:timeout, {GenServer, :call, _}} -> {:error, :timeout}
  end

  @doc """
  Look up the manifest, loading it from S3 (or rebuilding from a LIST)
  if the local cache is empty. Never triggers a CAS — pure read.

  Refreshes stale cache entries with a **conditional GET**: when the
  cached entry is older than `refresh_stale_ms` (default 1000ms), we
  issue `get_if_none_match` with the cached ETag. A 304 is a single
  small S3 round-trip and touches the entry's freshness timestamp; a
  200 returns the fresh manifest and updates the cache. This is what
  closes the cross-node freshness gap: a node whose only local writer
  is idle still learns about segments other nodes have committed.

  A stale-refresh failure (network hiccup, S3 throttle) returns the
  stale cached entry rather than failing the query. The next query
  will try again.

  This is also the query-path entry point when a query arrives before
  the owner has been booted (a cold cache after a node restart) —
  that path routes through the owner, which does the initial load.
  """
  @spec ensure_loaded(String.t(), String.t(), map()) ::
          {:ok, ManifestCache.entry()} | {:error, term()}
  def ensure_loaded(tenant, signal, config), do: ensure_loaded(tenant, signal, config, [])

  @doc "Required snapshots always validate the root with S3 and never serve stale cache or reconstruct missing authority."
  def ensure_loaded(tenant, signal, config, opts) when is_binary(tenant) and is_binary(signal) and is_map(config) do
    if Keyword.get(opts, :require_fresh_manifest, false) do
      required_snapshot(tenant, signal, config)
    else
      cached_snapshot(tenant, signal, config)
    end
  end

  defp required_snapshot(tenant, signal, config) do
    {entry, token} = ManifestCache.snapshot(tenant, signal)
    etag = if entry, do: entry.etag
    version = if entry, do: entry.manifest.version

    case Retention.fetch_root(tenant, signal, config, etag, version) do
      :not_modified when is_map(entry) ->
        ManifestCache.touch(tenant, signal, token)
        {:ok, %{manifest: entry.manifest, etag: entry.etag, refreshed_at_mono: System.monotonic_time(:millisecond)}}

      {:ok, fresh_etag, body} ->
        case decode_manifest(body, tenant, signal) do
          {:ok, manifest} ->
            cache_snapshot(tenant, signal, {manifest, body}, fresh_etag, token)

          {:error, _} = error ->
            ManifestCache.drop(tenant, signal)
            error
        end

      {:error, :not_found} ->
        ManifestCache.drop(tenant, signal)
        {:error, :signal_authority_missing}

      _ ->
        {:error, :manifest_freshness_unavailable}
    end
  end

  defp cache_snapshot(tenant, signal, {manifest, _body} = encoded, etag, token) do
    ManifestCache.put_snapshot(tenant, signal, encoded, etag, token)
    {:ok, %{manifest: manifest, etag: etag, refreshed_at_mono: System.monotonic_time(:millisecond)}}
  end

  defp cached_snapshot(tenant, signal, config) do
    case ManifestCache.get(tenant, signal) do
      %{} = entry ->
        case maybe_refresh(entry, tenant, signal, config) do
          {:error, _} = error -> error
          refreshed -> {:ok, refreshed}
        end

      nil ->
        with {:ok, pid} <- ensure_started(tenant, signal, config),
             {:ok, {:encoded, payload, etag}} <- call_owner(pid, :ensure_loaded, 15_000),
             {:ok, manifest} <- Manifest.decode(payload) do
          {:ok, %{manifest: manifest, etag: etag, refreshed_at_mono: System.monotonic_time(:millisecond)}}
        end
    end
  end

  # A cached entry is considered fresh for `refresh_stale_ms`
  # milliseconds after its last refresh. Beyond that we issue a
  # conditional GET so a manifest another node committed becomes
  # visible without waiting for a local write. The refresh happens on
  # the caller's process (the query path) — not through the owner —
  # with a conditional ETS replacement: a delayed reader may return its own
  # validated snapshot, but must never regress a newer cached publication.
  defp maybe_refresh(entry, tenant, signal, config) do
    if stale?(entry, config) do
      refresh(entry, tenant, signal, config)
    else
      entry
    end
  end

  defp stale?(entry, config) do
    interval_ms = Map.get(config, :refresh_stale_ms, @default_refresh_stale_ms)
    System.monotonic_time(:millisecond) - entry.refreshed_at_mono >= interval_ms
  end

  defp refresh(entry, tenant, signal, config) do
    case Retention.fetch_root(tenant, signal, config, entry.etag, entry.manifest.version) do
      :not_modified ->
        # No new writes; just touch the freshness timestamp so we don't
        # keep issuing 304s on every query.
        ManifestCache.touch(tenant, signal, entry.token)
        %{entry | refreshed_at_mono: System.monotonic_time(:millisecond)}

      {:ok, new_etag, body} ->
        case decode_manifest(body, tenant, signal) do
          {:ok, manifest} ->
            ManifestCache.put_snapshot(tenant, signal, {manifest, body}, new_etag, entry.token)

            %{
              manifest: manifest,
              etag: new_etag,
              refreshed_at_mono: System.monotonic_time(:millisecond)
            }

          {:error, _} = error ->
            # A fetched undecodable authority is not a transport failure.
            # Never hide corruption/new formats behind stale successful data.
            ManifestCache.drop(tenant, signal)
            error
        end

      {:error, :not_found} when entry.manifest.version == 3 ->
        {:error, :managed_manifest_missing}

      {:error, _} = error ->
        stale_or_error(entry, error, tenant, signal, config)
    end
  end

  # A format-3 root may already have reclaimed the segments a stale snapshot
  # references, so a managed prefix fails closed. A cached legacy root keeps
  # serving its last snapshot, as before retention existed, unless the prefix
  # has become managed. The marker probe is advisory here: if it fails too,
  # only a node enforcing retention for this signal fails closed.
  defp stale_or_error(%{manifest: %Manifest{version: 3}}, error, _tenant, _signal, _config), do: error

  defp stale_or_error(entry, error, tenant, signal, config) do
    case PagedManifest.managed?(config, tenant, signal) do
      {:ok, false} ->
        entry

      {:ok, true} ->
        if error == {:error, :not_found}, do: {:error, :managed_manifest_missing}, else: error

      {:error, _} ->
        if Retention.enforcing?(config, signal), do: error, else: entry
    end
  end

  # ---- supervision helpers --------------------------------------------------

  @doc """
  Look up (or start) the owner process for a given `(tenant, signal)`.
  Starting is idempotent via `Registry`-based `:via` naming — two
  racing starts collapse to one process.
  """
  @spec ensure_started(String.t(), String.t(), map()) ::
          {:ok, pid()} | {:error, term()}
  def ensure_started(tenant, signal, config) do
    # Raw ETS lookup can retain an exited owner until registry cleanup runs.
    # The via-name lookup checks liveness before reusing that process.
    case Registry.whereis_name({@registry, {tenant, signal}}) do
      pid when is_pid(pid) ->
        {:ok, pid}

      :undefined ->
        opts = [tenant: tenant, signal: signal, config: config]
        spec = %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :transient}

        case DynamicSupervisor.start_child(Pulse.Runtime.name(ManifestSupervisor), Pulse.Runtime.child_spec(spec)) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _} = err -> err
        end
    end
  end

  @doc """
  Apply a maintenance change to the root of `(tenant, signal)`, serialized with
  this node's ingest publications.

  `fun.(root)` runs inside the owner against its current root and returns
  `{:write, updated, payload, result}` to publish `payload` (the encoding of
  `updated`) with a conditional write, `{:done, result}` when nothing needs to
  change, or `{:error, reason}`. A conflicting write by another instance reloads
  the root and runs `fun` again, up to five times. Returns `{:ok, result}`.

  Compaction and cleanup used to read and rewrite the root on their own, so on
  a prefix whose appends commit back to back their conditional writes kept
  losing to ingest. Local appends now wait for the transaction and are applied
  on top of it; conditional writes still order this owner against other
  instances.
  """
  @spec transact(String.t(), String.t(), map(), (Manifest.t() -> term()), timeout()) ::
          {:ok, term()} | {:error, term()}
  def transact(tenant, signal, config, fun, timeout \\ 120_000)
      when is_binary(tenant) and is_binary(signal) and is_map(config) and is_function(fun, 1) do
    with {:ok, pid} <- ensure_started(tenant, signal, config),
         do: call_owner(pid, {:transact, fun, config}, timeout)
  end

  @spec start_link(opts()) :: Elixir.GenServer.on_start()
  def start_link(opts) do
    tenant = Keyword.fetch!(opts, :tenant)
    signal = Keyword.fetch!(opts, :signal)
    name = {:via, Registry, {@registry, {tenant, signal}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # ---- GenServer callbacks --------------------------------------------------

  @impl true
  def init(opts) do
    Process.set_label({:pulse, :manifest_owner})

    state = %{
      tenant: Keyword.fetch!(opts, :tenant),
      signal: Keyword.fetch!(opts, :signal),
      config: Keyword.fetch!(opts, :config),
      flush_interval_ms: Keyword.get(opts, :flush_interval_ms, @default_flush_interval_ms),
      flush_batch_max: Keyword.get(opts, :flush_batch_max, @default_flush_batch_max),
      # Minimum spacing between publication starts (ms) and the last start.
      commit_interval_ms: opts |> Keyword.fetch!(:config) |> Map.get(:ingest_flush_interval_ms, 0),
      committed_at: nil,
      manifest: nil,
      etag: nil,
      loaded?: false,
      pending: [],
      waiters: [],
      # Maintenance transactions waiting for the next spaced publication,
      # newest first; see `handle_call({:transact, ...})`.
      transactions: [],
      timer_ref: nil,
      # Whether the pending flush timer only waits for appends to share a
      # queued maintenance change's publication (see `await_appends/1`).
      timer_fallback?: false,
      # Moving average of recent publication durations (ms); see commit_eta/2.
      commit_ms: nil,
      # Heap words after the last full sweep and publications since; see
      # collect_garbage/1.
      swept_words: 0,
      unswept: 0
    }

    # Load on the first request so an initial registration can create the
    # complete manifest in its publication CAS, without an intermediate PUT.
    {:ok, state, @idle_hibernate_ms}
  end

  @impl true
  def handle_call(:ensure_loaded, _from, state) do
    # A cache miss must not turn an old owner snapshot into a fresh query
    # snapshot after another node has published compaction or new ingest.
    token = ManifestCache.token(state.tenant, state.signal)

    case load_manifest(state) do
      {:ok, manifest, etag} ->
        # Reply with the encoded bytes: a decoded manifest sent as a message is
        # flattened, losing the summary sharing the caller regains by decoding.
        payload = encode_cached(manifest)
        ManifestCache.put_snapshot(state.tenant, state.signal, {manifest, payload}, etag, token)
        state = %{state | manifest: manifest, etag: etag, loaded?: true}
        {:reply, {:ok, {:encoded, payload, etag}}, state, @idle_hibernate_ms}

      {:error, _} = error ->
        {:reply, error, state, @idle_hibernate_ms}
    end
  end

  def handle_call({:register_segments, segments}, from, state),
    do: handle_call({:register_segments, segments, System.monotonic_time()}, from, state)

  def handle_call({:register_segments, segments, sent}, from, state) do
    if state.loaded? do
      enqueue_and_maybe_flush(state, from, segments, sent)
    else
      token = ManifestCache.token(state.tenant, state.signal)

      case load_manifest(state, false) do
        {:ok, manifest, etag} ->
          # A rebuilt manifest without an ETag is not yet published. Do not
          # expose it through the shared query cache until the CAS succeeds.
          cache_loaded(state, manifest, etag, token)

          state
          |> Map.merge(%{manifest: manifest, etag: etag, loaded?: true})
          |> enqueue_and_maybe_flush(from, segments, sent)

        {:error, _} = err ->
          {:reply, err, state, @idle_hibernate_ms}
      end
    end
  end

  def handle_call({:transact, fun, config}, from, state) do
    owner_config = state.config

    case loaded_for_transaction(%{state | config: config}) do
      # With spaced publications, a paged root's maintenance change shares
      # the next publication's conditional write with the appends and other
      # changes queued by then, instead of writing the root once more.
      {:ok, %{manifest: %{version: 4}} = loaded} when state.commit_interval_ms > 0 ->
        loaded = %{loaded | config: owner_config, transactions: [{from, fun} | loaded.transactions]}
        {:noreply, await_appends(loaded)}

      {:ok, loaded} ->
        {reply, updated} = run_transaction(loaded, fun, @cas_max_retries)
        {:reply, reply, %{updated | config: owner_config}, @idle_hibernate_ms}

      {:error, _} = error ->
        {:reply, error, state, @idle_hibernate_ms}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    do_flush(state)
  end

  def handle_info(:timeout, state) do
    # `:hibernate` compacts the process heap and drops the stack; a
    # manual `garbage_collect/1` beforehand would be redundant.
    {:noreply, state, :hibernate}
  end

  # Maintenance needs a published root: never one rebuilt from a LIST.
  defp loaded_for_transaction(%{loaded?: true, etag: etag} = state) when is_binary(etag),
    do: {:ok, adopt_cached_root(state)}

  defp loaded_for_transaction(state) do
    token = ManifestCache.token(state.tenant, state.signal)

    case load_manifest(state, false) do
      {:ok, manifest, etag} when is_binary(etag) ->
        cache_loaded(state, manifest, etag, token)
        {:ok, %{state | manifest: manifest, etag: etag, loaded?: true}}

      {:ok, _rebuilt, nil} ->
        {:error, :not_found}

      {:error, _} = error ->
        error
    end
  end

  defp run_transaction(state, _fun, 0), do: {{:error, :cas_retries_exhausted}, state}

  defp run_transaction(state, fun, attempts) do
    case fun.(state.manifest) do
      {:write, updated, payload, result} -> write_transaction(state, fun, attempts, {updated, payload, result})
      {:done, result} -> {{:ok, result}, state}
      {:error, _} = error -> {error, state}
    end
  end

  defp write_transaction(state, fun, attempts, {updated, payload, result}) do
    base = ManifestCache.publication_base(state.tenant, state.signal)
    key = Manifest.manifest_key(state.tenant, state.signal)

    case ObjectStore.put_if_match(state.config, key, payload, state.etag) do
      {:ok, etag} ->
        ManifestCache.publish(state.tenant, state.signal, {updated, payload}, etag, state.etag, base)
        {{:ok, result}, %{state | manifest: updated, etag: etag}}

      {:error, :precondition_failed} ->
        retry_transaction(state, fun, attempts)

      # The write may still have landed; the next publication's conditional
      # write finds out and reloads.
      {:error, _} = error ->
        {error, state}
    end
  end

  defp retry_transaction(state, fun, attempts) do
    case load_manifest(state, false) do
      {:ok, manifest, etag} when is_binary(etag) ->
        run_transaction(%{state | manifest: manifest, etag: etag}, fun, attempts - 1)

      {:ok, _rebuilt, nil} ->
        {{:error, :not_found}, state}

      {:error, _} = error ->
        {error, state}
    end
  end

  defp cache_loaded(_state, _manifest, nil, _token), do: :ok

  # Encode through the owner's wire cache, which the next publication needs
  # anyway; a bare manifest would make the cache run a second, uncached encode.
  defp cache_loaded(state, manifest, etag, token),
    do: ManifestCache.put_snapshot(state.tenant, state.signal, {manifest, encode_cached(manifest)}, etag, token)

  # ---- flush pipeline -------------------------------------------------------

  # Enqueue the caller's segments, register them as a waiter, and — if
  # the batch cap trips — flush immediately instead of waiting for the
  # timer. Under bursty load this bounds tail latency.
  defp enqueue_and_maybe_flush(state, from, segments, sent) do
    waiter = {from, segments, sent}
    state = %{state | pending: state.pending ++ segments, waiters: [waiter | state.waiters]}
    publish_queue_depth(state)

    cond do
      length(state.pending) >= state.flush_batch_max -> cancel_timer(state) |> do_flush()
      state.timer_fallback? -> {:noreply, state |> cancel_timer() |> ensure_flush_timer()}
      true -> {:noreply, ensure_flush_timer(state)}
    end
  end

  defp ensure_flush_timer(%{timer_ref: nil} = state),
    do: %{state | timer_ref: Process.send_after(self(), :flush, flush_delay(state))}

  defp ensure_flush_timer(state), do: state

  # A queued maintenance change rides the next publication appends start, so
  # it never takes a spacing slot an append would then wait a whole window
  # for. Without appends it publishes on its own after two windows.
  defp await_appends(%{timer_ref: nil} = state) do
    delay = max(flush_delay(state), 2 * state.commit_interval_ms)
    %{state | timer_ref: Process.send_after(self(), :flush, delay), timer_fallback?: true}
  end

  defp await_appends(state), do: state

  # While publishing, `committing` is `{started_ms, queued}`: the publication
  # start and the segments deferred to a later one. Gauges keep counting the
  # segments and waiters in flight.
  defp publish_queue_depth(state, committing \\ nil) do
    {committing_since, queued} = committing || {nil, length(state.pending)}

    Registry.update_value(@registry, {state.tenant, state.signal}, fn _ ->
      %{
        pending: length(state.pending),
        waiters: length(state.waiters),
        queued: queued,
        committing_since: committing_since,
        commit_ms: state.commit_ms,
        flush_interval_ms: state.flush_interval_ms
      }
    end)
  end

  @doc """
  When the owner of `(tenant, signal)` is publishing, a map with the
  publication's start (`:since`) and expected end (`:eta`) in monotonic
  milliseconds, the duration `:estimate`, the owner's `:flush_interval_ms` and
  its `:queued` segments; otherwise `nil`. Reads the owner's registry value,
  without messaging it. The estimate is a moving average of recent
  publications, so it is only a hint for scheduling, never for correctness.
  """
  def commit_eta(tenant, signal) do
    case Registry.lookup(@registry, {tenant, signal}) do
      [{_pid, %{committing_since: since, commit_ms: estimate} = info}]
      when is_integer(since) and is_integer(estimate) ->
        %{
          since: since,
          eta: since + estimate,
          estimate: estimate,
          flush_interval_ms: info.flush_interval_ms,
          queued: info.queued
        }

      _ ->
        nil
    end
  rescue
    ArgumentError -> nil
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: ref} = state) do
    # If `cancel_timer/1` returns `false`, the timer already fired and
    # the `:flush` message is already in our mailbox. Drain it so we
    # don't fire two flushes back-to-back (a wasted CAS on an empty
    # pending queue, but also a subtle re-entry through `do_flush/1`).
    case Process.cancel_timer(ref) do
      false ->
        receive do
          :flush -> :ok
        after
          0 -> :ok
        end

      _ ->
        :ok
    end

    %{state | timer_ref: nil, timer_fallback?: false}
  end

  # Copy a cached root only when another path (retention) replaced it.
  defp adopt_cached_root(state) do
    with {version, etag, _token} when version in [3, 4] and etag != state.etag <-
           ManifestCache.info(state.tenant, state.signal),
         %{manifest: %{version: ^version} = manifest, etag: ^etag} <- ManifestCache.get(state.tenant, state.signal) do
      %{state | manifest: manifest, etag: etag, loaded?: true}
    else
      _ -> state
    end
  end

  defp do_flush(%{pending: [], transactions: []} = state) do
    {:noreply, %{state | timer_ref: nil, timer_fallback?: false}, @idle_hibernate_ms}
  end

  defp do_flush(state) do
    base = ManifestCache.publication_base(state.tenant, state.signal)
    state = %{state | timer_ref: nil, timer_fallback?: false, committed_at: System.monotonic_time(:millisecond)}

    state = adopt_cached_root(state)

    {state, deferred} = partition_waiters(state)
    started = System.monotonic_time()
    for {_from, _segments, enqueued} <- state.waiters, do: Pulse.Metrics.stage(state.signal, :manifest_wait, enqueued)
    remaining = Enum.flat_map(deferred, &elem(&1, 1))

    publish_queue_depth(
      %{state | pending: state.pending ++ remaining, waiters: state.waiters ++ deferred},
      {System.convert_time_unit(started, :native, :millisecond), length(remaining)}
    )

    result = cas_with_retry(state, state.pending, @cas_max_retries)
    for _waiter <- state.waiters, do: Pulse.Metrics.stage(state.signal, :manifest_commit, started)
    observe_commit(state, result, started)
    state = %{state | commit_ms: average_commit(state.commit_ms, started)}
    publish_queue_depth(%{state | pending: remaining, waiters: deferred})

    case result do
      {kind, manifest, etag, outcomes} when kind in [:ok, :skipped] ->
        # Rejected-only attempts performed neither CAS nor a fresh authority
        # read. Their private root must never repopulate an invalidated cache.
        if kind == :ok,
          do: ManifestCache.publish(state.tenant, state.signal, published(manifest, etag), etag, state.etag, base)

        warn_flat_growth(state, manifest)

        Enum.each(outcomes, fn {from, result} -> GenServer.reply(from, result) end)
        state = %{state | transactions: []}
        state = collect_garbage(state)

        {:noreply,
         %{
           state
           | manifest: manifest,
             etag: etag,
             loaded?: true,
             pending: remaining,
             waiters: deferred
         }
         |> schedule_deferred(), @idle_hibernate_ms}

      {:error, reason} = err ->
        {_eligible, outcomes} = publication_requests(state)
        Enum.each(outcomes, fn {from, outcome} -> GenServer.reply(from, failure_reply(outcome, err)) end)
        Enum.each(state.transactions, fn {from, _fun} -> GenServer.reply(from, err) end)
        state = %{state | transactions: []}

        Logger.warning("manifest CAS gave up tenant=#{state.tenant} signal=#{state.signal} reason=#{inspect(reason)}")

        # Keep the process alive: the next register_segments will start
        # from a clean slate (and if the underlying failure was
        # transient, the next flush will succeed).
        {:noreply, %{state | pending: remaining, waiters: deferred} |> schedule_deferred(), @idle_hibernate_ms}
    end
  end

  # One publication's duration by its root's encoded size: flat roots make it
  # grow with history, paged roots keep it flat.
  defp observe_commit(state, {kind, manifest, _etag, _outcomes}, started) when kind in [:ok, :skipped] do
    bytes =
      case Process.delete(@published_bytes) do
        bytes when is_integer(bytes) -> bytes
        _ -> nil
      end

    if bytes, do: Pulse.Metrics.manifest_commit(state.signal, manifest.version, bytes, started)
  end

  defp observe_commit(_state, _result, _started), do: Process.delete(@published_bytes)

  # A flat root is decoded, merged and encoded whole on every publication, and
  # replaced roots and payloads land on the old heap, which the default
  # generational GC (fullsweep_after 65535) only reclaims when it fills. Owners
  # of large roots then sat at two to three times their live manifest and kept
  # superseded multi-megabyte payload binaries alive. A full sweep once the heap
  # has doubled since the last one bounds that at about twice the live data.
  # It runs after waiters are replied to, so it never delays an acknowledgment.
  # Every hundredth publication sweeps too, so the mark follows live data that
  # shrank, as when a flat root converts to a paged one; owners of small roots
  # stay under the floor otherwise.
  @sweep_floor_words div(8 * 1_048_576, 8)
  @sweep_every 100
  defp collect_garbage(state) do
    {:total_heap_size, words} = Process.info(self(), :total_heap_size)

    if words > max(2 * state.swept_words, @sweep_floor_words) or
         (state.unswept >= @sweep_every and words > div(@sweep_floor_words, 8)) do
      :erlang.garbage_collect()
      {:total_heap_size, swept} = Process.info(self(), :total_heap_size)
      %{state | swept_words: swept, unswept: 0}
    else
      %{state | unswept: state.unswept + 1}
    end
  end

  # Flat manifests are rewritten whole on every flush and decoded by every
  # query, so their cost grows with history. Say so, rarely.
  @flat_warning_segments 20_000
  defp warn_flat_growth(state, %Manifest{version: version, segments: segments}) when version in [1, 2] do
    count = length(segments)

    if count >= @flat_warning_segments and Pulse.SelfMetrics.due?({:flat_manifest, state.signal}, 600_000) do
      Logger.warning(
        "flat #{state.signal} manifest tenant=#{state.tenant} has #{count} segments and grows with every append; " <>
          "set PULSE_MANIFEST_FORMAT=paged (the default) to bound manifest memory and publication cost"
      )
    end
  end

  defp warn_flat_growth(_state, _manifest), do: :ok

  # Weighted toward recent publications: flat roots grow steadily, and a
  # conflict retry should not dominate the estimate for long.
  defp average_commit(previous, started) do
    elapsed = System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
    if previous, do: div(previous * 3 + elapsed, 4), else: elapsed
  end

  # An eligible caller shares the publication failure; an ineligible one keeps its own reason.
  defp failure_reply(:ok, error), do: error
  defp failure_reply(outcome, _error), do: outcome

  defp schedule_deferred(%{pending: []} = state), do: state
  defp schedule_deferred(state), do: %{state | timer_ref: Process.send_after(self(), :flush, flush_delay(state))}

  # The flush timer, stretched so publications start at most once per
  # `commit_interval_ms`. Without an interval this is the plain timer.
  defp flush_delay(%{committed_at: last, commit_interval_ms: interval} = state)
       when is_integer(last) and interval > 0 do
    wait = last + interval - System.monotonic_time(:millisecond)
    max(state.flush_interval_ms, wait)
  end

  defp flush_delay(state), do: state.flush_interval_ms

  defp partition_waiters(%{manifest: %{version: 3}} = state) do
    {selected, deferred, _, _, _} =
      Enum.reduce(Enum.reverse(state.waiters), {[], [], MapSet.new(), 0, 0}, fn {from, segments, _enqueued} = waiter,
                                                                                {selected, deferred, starts, count,
                                                                                 bytes} ->
        own = MapSet.new(segments, &PagedManifest.bucket_start(state.manifest.paging, &1.max_ts))
        union = MapSet.union(starts, own)
        wire_bytes = IO.iodata_length(Pulse.JSON.encode_to_iodata!(Enum.map(segments, &Segment.to_wire/1)))

        cond do
          MapSet.size(own) > 4 or length(segments) > 256 or wire_bytes > 65_536 ->
            GenServer.reply(from, {:error, :retention_capacity})
            {selected, deferred, starts, count, bytes}

          MapSet.size(union) <= 4 and count + length(segments) <= 256 and bytes + wire_bytes <= 65_536 ->
            {[waiter | selected], deferred, union, count + length(segments), bytes + wire_bytes}

          true ->
            {selected, [waiter | deferred], starts, count, bytes}
        end
      end)

    {%{state | waiters: selected, pending: Enum.flat_map(selected, &elem(&1, 1))}, deferred}
  end

  defp partition_waiters(state), do: {state, []}

  # One CAS attempt. Any failure reads the root back once: that read
  # resolves a lost response and, on `:precondition_failed` or
  # `:already_exists` (a first-create race), seeds the retry.
  # Every retry rebuilds the merged manifest against the freshest known
  # ETag, so we never overwrite a concurrent writer's segments.
  @cas_conflicts [:precondition_failed, :already_exists]

  defp cas_with_retry(_state, _segments, 0), do: {:error, :cas_retries_exhausted}

  defp cas_with_retry(state, segments, retries_left) do
    {eligible, outcomes} = publication_requests(state)
    {applied, transaction_outcomes, written?} = apply_transactions(state)
    outcomes = outcomes ++ transaction_outcomes

    if segments == [] and not written? do
      {:skipped, state.manifest, state.etag, outcomes}
    else
      publish_prepared(state, applied, segments, eligible, outcomes, written?, retries_left)
    end
  end

  # Queued maintenance changes, oldest first, each against the root the
  # previous one left; appends are applied on top of the result. A conflict
  # reloads the root and runs them all again, as a transaction alone would.
  defp apply_transactions(%{transactions: []} = state), do: {state, [], false}

  defp apply_transactions(state) do
    {manifest, outcomes, written?} =
      state.transactions
      |> Enum.reverse()
      |> Enum.reduce({state.manifest, [], false}, fn {from, fun}, {manifest, outcomes, written?} ->
        case run_folded(fun, manifest) do
          {:write, %Manifest{version: 4} = updated, _payload, result} ->
            {updated, [{from, {:ok, result}} | outcomes], true}

          {:write, _updated, _payload, _result} ->
            {manifest, [{from, {:error, :manifest_version_changed}} | outcomes], written?}

          {:done, result} ->
            {manifest, [{from, {:ok, result}} | outcomes], written?}

          {:error, _} = error ->
            {manifest, [{from, error} | outcomes], written?}
        end
      end)

    {%{state | manifest: manifest}, Enum.reverse(outcomes), written?}
  end

  # One failing change must not take the appends sharing its publication down.
  defp run_folded(fun, manifest) do
    fun.(manifest)
  rescue
    exception -> {:error, {:transaction_raised, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:transaction_exited, {kind, reason}}}
  end

  defp publish_prepared(state, applied, segments, eligible, outcomes, written?, retries_left) do
    applied
    |> prepare_publication(segments, eligible)
    |> seal(state)
    |> case do
      {:skip, manifest} ->
        {:skipped, manifest, state.etag, outcomes}

      {:ok, merged, payload} ->
        attempt = %{
          state: state,
          segments: segments,
          retries_left: retries_left,
          merged: merged,
          payload: payload,
          eligible: eligible,
          outcomes: outcomes,
          written?: written?
        }

        publish(attempt)

      {:error, :manifest_page_missing} when retries_left > 1 ->
        reload_and_retry(state, segments, retries_left)

      error ->
        error
    end
  end

  # A managed root with no eligible caller publishes nothing.
  defp prepare_publication(%{manifest: %{version: 3} = manifest}, _segments, []), do: {:skip, manifest}

  defp prepare_publication(%{manifest: %{version: 3}} = state, _segments, eligible),
    do: PagedManifest.register(state.manifest, eligible, state.tenant, state.signal, state.config)

  defp prepare_publication(%{manifest: %{version: 4}} = state, segments, _eligible),
    do: JournalManifest.register(state.manifest, segments, state.tenant, state.signal, state.config)

  # A flat root is converted by the publication that next changes it. A failed
  # conversion (an unreachable store, an unexpected key) keeps it flat for now:
  # ingest must not depend on the conversion succeeding.
  defp prepare_publication(state, segments, _eligible) do
    if state.manifest.version in [1, 2] and JournalManifest.enabled?(state.config, state.signal) do
      case convert(state) do
        {:ok, root} -> JournalManifest.register(root, segments, state.tenant, state.signal, state.config)
        :flat -> {:ok, Manifest.merge(state.manifest, segments)}
      end
    else
      {:ok, Manifest.merge(state.manifest, segments)}
    end
  end

  defp convert(state) do
    started = System.monotonic_time(:millisecond)

    case JournalManifest.convert(state.manifest, state.tenant, state.signal, state.config) do
      {:ok, root} ->
        Logger.info(
          "converting #{state.signal} manifest tenant=#{state.tenant} to the paged format: " <>
            "#{length(state.manifest.segments)} segments in #{System.monotonic_time(:millisecond) - started} ms"
        )

        {:ok, root}

      {:error, reason} ->
        if Pulse.SelfMetrics.due?({:manifest_conversion, state.signal}, 60_000) do
          Logger.warning(
            "keeping flat #{state.signal} manifest tenant=#{state.tenant}: conversion failed #{inspect(reason)}"
          )
        end

        :flat
    end
  end

  # A paged root spills its tail while encoding; publish exactly what was sealed.
  defp seal({:ok, %{version: 4} = merged}, state) do
    case JournalManifest.seal(merged, state.tenant, state.signal, state.config, Process.get(@wire_cache, %{})) do
      {:ok, {sealed, payload, cache}} ->
        Process.put(@wire_cache, cache)
        {:ok, sealed, payload}

      {:error, _} = error ->
        error
    end
  end

  defp seal({:ok, merged}, _state), do: {:ok, merged, encode_cached(merged)}
  defp seal(other, _state), do: other

  defp publish(%{state: state, payload: payload} = attempt) do
    case attempt_cas(state, payload) do
      {:ok, new_etag} ->
        # Let the cache store these exact bytes instead of encoding again.
        Process.put(@published_payload, {new_etag, payload})
        Process.put(@published_bytes, byte_size(payload))
        {:ok, attempt.merged, new_etag, attempt.outcomes}

      {:error, _} = error ->
        # Resolve internally retried/lost CAS responses before returning failure.
        state |> load_manifest(false) |> resolve_cas_failure(Map.put(attempt, :error, error))
    end
  end

  # Flat roots are rewritten whole on every flush; reuse each unchanged
  # segment's encoded JSON so a flush encodes only what changed. The cache is a
  # disposable owner-local optimization holding only the current segments.
  defp encode_cached(manifest) do
    {iodata, cache} = Manifest.encode(manifest, Process.get(@wire_cache, %{}))
    Process.put(@wire_cache, cache)
    IO.iodata_to_binary(iodata)
  end

  defp published(manifest, etag) do
    case Process.delete(@published_payload) do
      {^etag, payload} -> {manifest, payload}
      _ -> manifest
    end
  end

  defp resolve_cas_failure({:ok, %{version: version} = current, etag}, attempt) when version in [3, 4],
    do: resolve_managed_failure(current, etag, attempt)

  # A fresh legacy root can also prove that a lost response committed.
  # Never republish an already-visible unkeyed append merely to obtain an ACK.
  defp resolve_cas_failure({:ok, current, etag}, %{error: {:error, reason}} = attempt) when is_binary(etag) do
    keys = MapSet.new(current.segments, & &1.key)

    cond do
      Enum.all?(attempt.segments, &MapSet.member?(keys, &1.key)) ->
        {:ok, current, etag, attempt.outcomes}

      reason in @cas_conflicts ->
        retry_cas(attempt, %{attempt.state | manifest: current, etag: etag, loaded?: true})

      true ->
        attempt.error
    end
  end

  defp resolve_cas_failure({:error, _} = load_error, %{error: {:error, reason}}) when reason in @cas_conflicts,
    do: load_error

  defp resolve_cas_failure(_load, attempt), do: attempt.error

  defp resolve_managed_failure(current, etag, %{merged: merged, error: {:error, reason}} = attempt) do
    cond do
      merged.paging != nil and current.paging["nonce"] == merged.paging["nonce"] ->
        {:ok, current, etag, attempt.outcomes}

      merged.version != current.version ->
        retry_cas(attempt, %{attempt.state | manifest: current, etag: etag, loaded?: true})

      # Visible appends do not prove that folded maintenance changes landed.
      not Map.get(attempt, :written?, false) and publication_visible?(current, attempt.eligible, attempt.state) ->
        {:ok, current, etag, attempt.outcomes}

      reason in @cas_conflicts ->
        retry_cas(attempt, %{attempt.state | manifest: current, etag: etag})

      true ->
        attempt.error
    end
  end

  defp retry_cas(attempt, state), do: cas_with_retry(state, attempt.segments, attempt.retries_left - 1)

  # As for flat roots, only an active entry proves publication. A retired one
  # still needs this attempt's revision bump, which rearms deletion of the
  # object the retry may have uploaded again.
  defp publication_visible?(%{version: 4} = current, eligible, state) do
    Enum.all?(eligible, fn segment ->
      JournalManifest.lookup(current, segment, state.tenant, state.signal, state.config) == {:ok, :active}
    end)
  end

  defp publication_visible?(current, eligible, state) do
    case PagedManifest.with_budget(state.config, fn ->
           Enum.all?(
             eligible,
             &(PagedManifest.lookup(current, &1, state.tenant, state.signal, state.config, allow_closed: true) !=
                 :absent)
           )
         end) do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp publication_requests(%{manifest: %{version: 3}} = state) do
    now = System.system_time(:nanosecond)

    Enum.reduce(Enum.reverse(state.waiters), {[], []}, fn {from, segments, _enqueued}, {accepted, outcomes} ->
      result = eligibility(segments, state, now)
      {if(result == :ok, do: accepted ++ segments, else: accepted), [{from, result} | outcomes]}
    end)
  end

  defp publication_requests(state), do: {state.pending, Enum.map(state.waiters, fn {from, _, _} -> {from, :ok} end)}

  # The first ineligible segment decides the caller's outcome.
  defp eligibility(segments, state, now) do
    Enum.find_value(segments, :ok, fn segment ->
      case PagedManifest.eligible(state.manifest, segment, now, state.config) do
        :ok -> nil
        error -> error
      end
    end)
  end

  # `nil` etag means the owner has never seen this manifest; use
  # `put_if_none_match` so a first create is atomic. Any subsequent
  # update rides `put_if_match` against the ETag we remember.
  defp attempt_cas(state, payload) do
    key = Manifest.manifest_key(state.tenant, state.signal)

    case state.etag do
      nil ->
        with :ok <- PagedManifest.check_create(state.config, state.tenant, state.signal),
             do: ObjectStore.put_if_none_match(state.config, key, payload)

      etag ->
        ObjectStore.put_if_match(state.config, key, payload, etag)
    end
  end

  defp reload_and_retry(state, segments, retries_left) do
    case load_manifest(state) do
      {:ok, reloaded_manifest, reloaded_etag} ->
        cas_with_retry(
          %{state | manifest: reloaded_manifest, etag: reloaded_etag},
          segments,
          retries_left - 1
        )

      {:error, _} = err ->
        err
    end
  end

  defp decode_manifest(body, tenant, signal) do
    with {:ok, manifest} <- Manifest.decode(body),
         {:ok, :ok} <- PagedManifest.validate_context(manifest, tenant, signal),
         do: {:ok, manifest}
  end

  # ---- initial load / migration ---------------------------------------------

  defp load_manifest(state, publish_legacy? \\ true) do
    case Retention.fetch_root(
           state.tenant,
           state.signal,
           state.config,
           nil,
           if(state.loaded?, do: state.manifest.version)
         ) do
      {:ok, etag, body} ->
        case decode_manifest(body, state.tenant, state.signal) do
          {:ok, manifest} -> {:ok, manifest, etag}
          {:error, _} = err -> err
        end

      {:error, :not_found} ->
        rebuild_from_prefix(state, publish_legacy?)

      {:error, _} = err ->
        err
    end
  end

  # First-write migration: no manifest exists yet, so LIST the v4 prefix
  # and reconstitute one from the segments that are already in S3. Then
  # PUT it with `put_if_none_match`. If another node beats us to the
  # create, we lose gracefully and reload their version. The LIST is
  # recursive — the `date=/hour=` partitions are swept in one call.
  defp rebuild_from_prefix(state, publish_legacy?) do
    prefix = "tenants/#{state.tenant}/v4/signal=#{state.signal}/"

    with :ok <- PagedManifest.check_create(state.config, state.tenant, state.signal),
         {:ok, keys} <- ObjectStore.list(state.config, prefix) do
      publish_rebuilt_manifest(state, keys, publish_legacy?)
    end
  end

  defp publish_rebuilt_manifest(state, keys, publish_legacy?) do
    if Enum.any?(keys, &authoritative_manifest_required?/1) do
      # Once compacted, only the manifest can distinguish published replacements
      # from orphan uploads and retired sources. Never guess by listing objects.
      {:error, :compacted_manifest_missing}
    else
      manifest = Manifest.merge(Manifest.new(), rebuild_segments(keys))

      if publish_legacy?, do: publish_legacy_manifest(state, manifest), else: {:ok, manifest, nil}
    end
  end

  # Also fence dev buckets that exercised the unreleased trace receipt/marker
  # layout. Removing obsolete code must never authorize LIST resurrection.
  defp authoritative_manifest_required?(key) do
    base = Path.basename(key)

    Enum.any?(["-compact-", "-final-", "-rollup-", "-edge-"], &String.contains?(base, &1)) or
      String.contains?(key, "/retirements/") or String.contains?(key, "/backups/") or
      base == "retention.marker.json"
  end

  defp publish_legacy_manifest(state, manifest) do
    payload = manifest |> Manifest.encode() |> IO.iodata_to_binary()
    manifest_key = Manifest.manifest_key(state.tenant, state.signal)

    result =
      with :ok <- PagedManifest.check_create(state.config, state.tenant, state.signal),
           do: ObjectStore.put_if_none_match(state.config, manifest_key, payload)

    case result do
      {:ok, etag} -> {:ok, manifest, etag}
      {:error, :already_exists} -> reload_after_create_race(state, manifest_key)
      {:error, _} = err -> err
    end
  end

  # Only keys that parse cleanly to `<min_ts>-<max_ts>-….parquet` get into
  # the rebuilt manifest. Everything else — the manifest itself, future
  # sidecar files (`.bloom`, `.postings`, `.stats`), stray uploads —
  # resolves to `:skip`. Codex flagged the earlier "keep with nil bounds"
  # fallback: the rebuilt manifest would then fail to decode
  # (`Segment.from_wire/1` requires integer bounds), leaving the tenant
  # unrecoverable.
  defp rebuild_segments(keys) do
    Enum.flat_map(keys, fn key ->
      case segment_from_key(key) do
        {:ok, segment} -> [segment]
        :skip -> []
      end
    end)
  end

  defp reload_after_create_race(state, manifest_key) do
    with {:ok, etag, body} <- ObjectStore.get_if_none_match(state.config, manifest_key, nil),
         {:ok, manifest} <- decode_manifest(body, state.tenant, state.signal) do
      {:ok, manifest, etag}
    end
  end

  # A rebuild-derived segment gets its bounds from the key format
  # (`<min_ts>-<max_ts>-<suffix>.parquet`). Anything the writer would
  # never produce — the manifest itself, sidecar indexes, a stray
  # upload — resolves to `:skip` and stays out of the manifest. Nothing
  # else has integer bounds, and the manifest requires them.
  @sort_key_width 20

  # v4 layout places the segment basename
  # (`<min_ts>-<max_ts>-<suffix>.parquet`) under one or more partition
  # prefixes (`date=.../hour=.../`), so parsing the key only needs the
  # basename — not any assumption about how deep the partitioning goes.
  # Anything the writer would never produce (the manifest itself, sidecar
  # indexes, a stray upload) resolves to `:skip` and stays out of the
  # manifest.
  @spec segment_from_key(String.t()) :: {:ok, Segment.t()} | :skip
  @doc false
  def segment_from_key(key) do
    if String.ends_with?(key, ".parquet") do
      key
      |> Path.basename()
      |> parse_bounds(key)
    else
      :skip
    end
  end

  defp parse_bounds(basename, key) do
    case basename do
      <<min_str::binary-size(@sort_key_width), "-", max_str::binary-size(@sort_key_width), "-", _::binary>> ->
        with {min_ts, ""} <- Integer.parse(min_str),
             {max_ts, ""} <- Integer.parse(max_str) do
          {:ok, %Segment{key: key, min_ts: min_ts, max_ts: max_ts}}
        else
          _ -> :skip
        end

      _ ->
        :skip
    end
  end
end
