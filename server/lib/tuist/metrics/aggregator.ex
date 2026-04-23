defmodule Tuist.Metrics.Aggregator do
  @moduledoc """
  In-memory per-account aggregator backed by ETS. Counters and histograms live
  in a single `:set` table keyed by `{tag, account_id, metric_name, labels,
  ...}` — counter bumps use `:ets.update_counter/3`, which is atomic and
  lockless, so concurrent telemetry handlers do not need to synchronise on the
  GenServer.

  Histogram observations still go through the owning process because they
  update several counters atomically (count, sum, and the matching bucket).
  Running those through a `cast` keeps the update simple without introducing a
  multi-counter race.

  If the aggregator process isn't running (e.g. a test that did not start the
  application supervisor), observations silently no-op — telemetry emission is
  not allowed to crash callers.

  ### Restarts and counter loss

  The ETS table is `:named_table` and owned by this GenServer. If the process
  crashes the table is destroyed and the supervisor restarts us from a clean
  slate. That is consistent with Prometheus semantics (the `rate`/`increase`
  functions are counter-reset-aware) but we still log a warning on every
  `init/1` beyond the first so ops notices if the process becomes flappy. The
  restart count is held in `:persistent_term` which survives process death.

  ### Cardinality and eviction

  The schema label vocabularies are bounded per-account by the **customer's**
  deployment shape, not globally. Left alone the table would grow with every
  new label combination, so the aggregator runs a periodic eviction sweep
  (default every 5 minutes) that drops entries for accounts whose scrape
  endpoint has not been hit recently (default 30 minutes). Actively scraped
  accounts keep their data; idle ones are reclaimed.

  Two telemetry events make the behaviour observable:

    * `[:tuist, :metrics, :aggregator, :stats]` — `%{size, memory_bytes,
      memory_words}`, published periodically so ops can alert on growth.
    * `[:tuist, :metrics, :aggregator, :evicted]` — `%{accounts, rows}`,
      published after each sweep that removed something.

  Attach a handler (Prometheus exporter, StatsD, log line) in prod.
  """

  use GenServer

  alias Tuist.Metrics.Schema

  require Logger

  @table :tuist_metrics_aggregator
  @last_scrape_table :tuist_metrics_last_scrape
  @counter_tag :c
  @histogram_tag :h
  @stats_event [:tuist, :metrics, :aggregator, :stats]
  @eviction_event [:tuist, :metrics, :aggregator, :evicted]
  @default_stats_interval_ms to_timeout(minute: 1)
  @default_eviction_interval_ms to_timeout(minute: 5)
  # Teams typically scrape every 15s–1min. 30 minutes is a comfortable
  # multiple of that — survives a collector restart or network blip —
  # while still bounding memory for accounts that stopped scraping.
  @default_scrape_staleness_ms to_timeout(minute: 30)

  # ---- Public API --------------------------------------------------------

  def start_link(opts \\ []) do
    init_opts = Keyword.take(opts, [:stats_interval_ms, :eviction_interval_ms, :scrape_staleness_ms])
    GenServer.start_link(__MODULE__, init_opts, Keyword.merge([name: __MODULE__], opts))
  end

  @doc """
  The telemetry event name under which the aggregator periodically
  publishes size and memory stats. Attach a handler in production to
  scrape this into your existing metrics pipeline or alerting.
  """
  def stats_event, do: @stats_event

  @doc """
  The telemetry event name emitted after each eviction sweep. The
  measurements carry the count of evicted accounts and deleted ETS
  rows so ops can see whether the aggregator's memory pressure is
  coming from expected churn or a cardinality bug.
  """
  def eviction_event, do: @eviction_event

  @doc """
  Atomically bumps a counter metric. Safe to call from any process; does not
  message the aggregator.
  """
  def increment_counter(account_id, metric, labels, count \\ 1) when is_integer(count) and count > 0 do
    if table_ready?() do
      key = counter_key(account_id, metric, labels)
      :ets.update_counter(@table, key, {2, count}, {key, 0})
      seed_last_scrape_if_absent(account_id)
    end

    :ok
  end

  @doc """
  Records a histogram observation. Routed through the aggregator process to
  keep the per-observation multi-update (count + sum + bucket) logically
  atomic.
  """
  def observe_histogram(account_id, metric, labels, value_seconds) when is_number(value_seconds) and value_seconds >= 0 do
    case GenServer.whereis(__MODULE__) do
      nil ->
        :ok

      pid ->
        GenServer.cast(pid, {:observe_histogram, account_id, metric, labels, value_seconds})
    end
  end

  @doc """
  Returns a list of metric observations for the given account on this node.
  Each entry is a map of shape:

      %{metric: "...", type: :counter, labels: {...}, value: 12}
      %{metric: "...", type: :histogram, labels: {...},
        count: 42, sum: 123.4, buckets: [{0.5, 3}, {1, 9}, ...]}

  Counter reads see every bump up to the moment they're called because
  `:ets.update_counter/3` is synchronous. Histogram reads are **eventually
  consistent**: observations go through a `GenServer.cast` so a scrape
  immediately following `observe_histogram/4` may miss it. Tests that
  assert on histogram state after emission should call
  `:sys.get_state(Aggregator)` first to flush the mailbox.
  """
  def snapshot(account_id) do
    if table_ready?() do
      # Every call that reaches here — local or cluster RPC during a
      # scrape — counts as activity for this account, so refresh its
      # last-scrape marker. Stops the eviction sweep from dropping data
      # that is still being consumed.
      record_scrape(account_id)

      counters =
        @table
        |> :ets.match_object({{@counter_tag, account_id, :_, :_}, :_})
        |> Enum.map(&counter_entry/1)

      counters ++ histogram_entries(account_id)
    else
      []
    end
  end

  @doc """
  Refreshes the last-seen timestamp for an account. `snapshot/1` calls
  this automatically; exposed separately so a caller (e.g. a test or a
  cluster-wide scrape coordinator) can mark an account as active
  without also reading its data.
  """
  def record_scrape(account_id) do
    if last_scrape_table_ready?() do
      :ets.insert(@last_scrape_table, {account_id, now_ms()})
    end

    :ok
  end

  defp seed_last_scrape_if_absent(account_id) do
    if last_scrape_table_ready?() do
      # `insert_new` only writes if the key is absent, so active
      # accounts (whose timestamps get refreshed on scrape) are not
      # perturbed by write throughput. Brand-new accounts get a clock
      # that starts ticking toward eviction from the first write.
      :ets.insert_new(@last_scrape_table, {account_id, now_ms()})
    end

    :ok
  end

  @doc """
  Clears all accumulated metrics and scrape timestamps. Primarily used
  by tests.
  """
  def reset do
    if table_ready?() do
      :ets.delete_all_objects(@table)
    end

    if last_scrape_table_ready?() do
      :ets.delete_all_objects(@last_scrape_table)
    end

    :ok
  end

  @doc """
  Returns size and memory information about the aggregator's ETS table.
  Intended for observability. The same data is published periodically
  as a `[:tuist, :metrics, :aggregator, :stats]` telemetry event; call
  this directly if you need an on-demand read.

  Returns `nil` if the table hasn't been created yet.
  """
  def table_info do
    if table_ready?() do
      word_size = :erlang.system_info(:wordsize)
      memory_words = :ets.info(@table, :memory)

      %{
        # Number of entries (one per counter, one per histogram bucket,
        # plus two per histogram for count + sum).
        size: :ets.info(@table, :size),
        memory_words: memory_words,
        memory_bytes: memory_words * word_size
      }
    end
  end

  # ---- GenServer ---------------------------------------------------------

  @impl true
  def init(opts) do
    # `:public` lets telemetry handlers bump counters without message-passing.
    # `read_concurrency` helps scrape traffic (all histogram reads stream
    # through ETS without contending with writers).
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(@last_scrape_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    log_restart_if_any()

    stats_interval_ms = Keyword.get(opts, :stats_interval_ms, @default_stats_interval_ms)
    eviction_interval_ms = Keyword.get(opts, :eviction_interval_ms, @default_eviction_interval_ms)
    scrape_staleness_ms = Keyword.get(opts, :scrape_staleness_ms, @default_scrape_staleness_ms)

    maybe_schedule(self(), :emit_stats, stats_interval_ms)
    maybe_schedule(self(), :evict_stale, eviction_interval_ms)

    {:ok,
     %{
       stats_interval_ms: positive_or_nil(stats_interval_ms),
       eviction_interval_ms: positive_or_nil(eviction_interval_ms),
       scrape_staleness_ms: scrape_staleness_ms
     }}
  end

  defp maybe_schedule(_pid, _msg, interval) when not is_integer(interval) or interval <= 0, do: :ok

  defp maybe_schedule(pid, msg, interval) do
    Process.send_after(pid, msg, interval)
    :ok
  end

  defp positive_or_nil(n) when is_integer(n) and n > 0, do: n
  defp positive_or_nil(_), do: nil

  defp log_restart_if_any do
    count = :persistent_term.get({__MODULE__, :init_count}, 0) + 1
    :persistent_term.put({__MODULE__, :init_count}, count)

    # Tests frequently start/restart the aggregator and would otherwise flood
    # the warning log. In prod, a second init is genuinely interesting — the
    # previous process crashed, which means we lost counters.
    if count > 1 and not Tuist.Environment.test?() do
      Logger.warning("Tuist.Metrics.Aggregator restarted (init_count=#{count}); counters for this node have been reset.")
    end
  end

  @impl true
  def handle_cast({:observe_histogram, account_id, metric, labels, value_seconds}, state) do
    case Schema.fetch(metric) do
      %{buckets: buckets} ->
        count_key = histogram_count_key(account_id, metric, labels)
        sum_key = histogram_sum_key(account_id, metric, labels)

        :ets.update_counter(@table, count_key, {2, 1}, {count_key, 0})

        # ETS counters are integers; scale seconds by 1000 to keep millisecond
        # precision in the sum without relying on floats.
        ms_increment = trunc(value_seconds * 1_000)
        :ets.update_counter(@table, sum_key, {2, ms_increment}, {sum_key, 0})

        Enum.each(buckets, fn bound ->
          if value_seconds <= bound do
            bucket_key = histogram_bucket_key(account_id, metric, labels, bound)
            :ets.update_counter(@table, bucket_key, {2, 1}, {bucket_key, 0})
          end
        end)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:emit_stats, state) do
    emit_stats()

    if interval = state.stats_interval_ms do
      Process.send_after(self(), :emit_stats, interval)
    end

    {:noreply, state}
  end

  def handle_info(:evict_stale, state) do
    evict_stale(state.scrape_staleness_ms)

    if interval = state.eviction_interval_ms do
      Process.send_after(self(), :evict_stale, interval)
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp evict_stale(staleness_ms) when is_integer(staleness_ms) and staleness_ms > 0 do
    if last_scrape_table_ready?() and table_ready?() do
      cutoff = now_ms() - staleness_ms

      # select_delete returns the number of rows removed from the scrape
      # table; the account_ids themselves come from a preceding select.
      stale_accounts =
        :ets.select(@last_scrape_table, [
          {{:"$1", :"$2"}, [{:<, :"$2", cutoff}], [:"$1"]}
        ])

      row_count = Enum.reduce(stale_accounts, 0, fn account_id, acc -> acc + evict_account(account_id) end)

      if stale_accounts != [] do
        :telemetry.execute(
          @eviction_event,
          %{accounts: length(stale_accounts), rows: row_count},
          %{staleness_ms: staleness_ms}
        )
      end
    else
      :ok
    end
  end

  defp evict_stale(_), do: :ok

  defp evict_account(account_id) do
    # Separate patterns for counter (4-tuple key) and histogram count/sum
    # (5-tuple key) and histogram bucket (6-tuple key). match_delete
    # returns :true but not the count, so approximate via a select first.
    counter_pattern = {{@counter_tag, account_id, :_, :_}, :_}
    histogram_meta_pattern = {{@histogram_tag, account_id, :_, :_, :_}, :_}
    histogram_bucket_pattern = {{@histogram_tag, account_id, :_, :_, :_, :_}, :_}

    removed =
      :ets.select_count(@table, [{counter_pattern, [], [true]}]) +
        :ets.select_count(@table, [{histogram_meta_pattern, [], [true]}]) +
        :ets.select_count(@table, [{histogram_bucket_pattern, [], [true]}])

    :ets.match_delete(@table, counter_pattern)
    :ets.match_delete(@table, histogram_meta_pattern)
    :ets.match_delete(@table, histogram_bucket_pattern)
    :ets.delete(@last_scrape_table, account_id)

    removed
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp last_scrape_table_ready?, do: :ets.whereis(@last_scrape_table) != :undefined

  defp emit_stats do
    case table_info() do
      nil ->
        :ok

      %{size: size, memory_bytes: memory_bytes, memory_words: memory_words} ->
        :telemetry.execute(
          @stats_event,
          %{size: size, memory_bytes: memory_bytes, memory_words: memory_words},
          %{}
        )
    end
  end

  # ---- Keys and decoding -------------------------------------------------

  defp counter_key(account_id, metric, labels), do: {@counter_tag, account_id, metric, labels}

  defp histogram_count_key(account_id, metric, labels), do: {@histogram_tag, account_id, metric, labels, :count}

  defp histogram_sum_key(account_id, metric, labels), do: {@histogram_tag, account_id, metric, labels, :sum}

  defp histogram_bucket_key(account_id, metric, labels, bound),
    do: {@histogram_tag, account_id, metric, labels, {:bucket, bound}}

  defp counter_entry({{@counter_tag, _account_id, metric, labels}, value}) do
    %{metric: metric, type: :counter, labels: labels, value: value}
  end

  defp histogram_entries(account_id) do
    for {{@histogram_tag, ^account_id, metric, labels, :count}, count} <-
          :ets.match_object(@table, {{@histogram_tag, account_id, :_, :_, :count}, :_}) do
      sum_ms =
        case :ets.lookup(@table, histogram_sum_key(account_id, metric, labels)) do
          [{_, v}] -> v
          [] -> 0
        end

      %{buckets: buckets} = Schema.fetch(metric)

      bucket_pairs =
        Enum.map(buckets, fn bound ->
          case :ets.lookup(@table, histogram_bucket_key(account_id, metric, labels, bound)) do
            [{_, v}] -> {bound, v}
            [] -> {bound, 0}
          end
        end)

      %{
        metric: metric,
        type: :histogram,
        labels: labels,
        count: count,
        sum: sum_ms / 1_000,
        buckets: bucket_pairs
      }
    end
  end

  defp table_ready?, do: :ets.whereis(@table) != :undefined
end
