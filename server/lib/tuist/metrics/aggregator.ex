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

  ### Cardinality caveat

  The schema label vocabularies are bounded per-account by the **customer's**
  deployment shape, not globally. A customer with thousands of projects,
  schemes, or Xcode versions can drive the ETS table to arbitrary size — there
  is no TTL/eviction policy in this process. Keep an eye on per-account
  cardinality (we may want to add a defensive cap in a future revision).
  """

  use GenServer

  require Logger

  alias Tuist.Metrics.Schema

  @table :tuist_metrics_aggregator
  @counter_tag :c
  @histogram_tag :h

  # ---- Public API --------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.merge([name: __MODULE__], opts))
  end

  @doc """
  Atomically bumps a counter metric. Safe to call from any process; does not
  message the aggregator.
  """
  def increment_counter(account_id, metric, labels, count \\ 1)
      when is_integer(count) and count > 0 do
    if table_ready?() do
      key = counter_key(account_id, metric, labels)
      :ets.update_counter(@table, key, {2, count}, {key, 0})
    end

    :ok
  end

  @doc """
  Records a histogram observation. Routed through the aggregator process to
  keep the per-observation multi-update (count + sum + bucket) logically
  atomic.
  """
  def observe_histogram(account_id, metric, labels, value_seconds)
      when is_number(value_seconds) and value_seconds >= 0 do
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
  Clears all accumulated metrics. Primarily used by tests.
  """
  def reset do
    if table_ready?() do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  # ---- GenServer ---------------------------------------------------------

  @impl true
  def init(:ok) do
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

    log_restart_if_any()
    {:ok, %{}}
  end

  defp log_restart_if_any do
    count = :persistent_term.get({__MODULE__, :init_count}, 0) + 1
    :persistent_term.put({__MODULE__, :init_count}, count)

    # Tests frequently start/restart the aggregator and would otherwise flood
    # the warning log. In prod, a second init is genuinely interesting — the
    # previous process crashed, which means we lost counters.
    if count > 1 and not Tuist.Environment.test?() do
      Logger.warning(
        "Tuist.Metrics.Aggregator restarted (init_count=#{count}); counters for this node have been reset."
      )
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

  # ---- Keys and decoding -------------------------------------------------

  defp counter_key(account_id, metric, labels),
    do: {@counter_tag, account_id, metric, labels}

  defp histogram_count_key(account_id, metric, labels),
    do: {@histogram_tag, account_id, metric, labels, :count}

  defp histogram_sum_key(account_id, metric, labels),
    do: {@histogram_tag, account_id, metric, labels, :sum}

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
