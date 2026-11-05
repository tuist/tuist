defmodule Pulse.Usage do
  @moduledoc """
  Per-tenant usage metering for billing and capacity planning.

  Each instance counts, per tenant and UTC hour, the ingest it acknowledged
  (requests, wire bytes and stored records per signal) and the queries it ran
  (requests and wall time). Counters live in a node-local ETS table and are
  flushed every `:flush_interval_ms` to one object per tenant, hour and
  instance:

      usage/v1/tenant=<tenant>/hour=<YYYY-MM-DDTHH>/<instance>.json

  The object holds the instance's cumulative totals for that hour, so a flush
  overwrites it, and a retried or repeated flush can never double-count. The
  instance identifier is random per boot, so restarts and concurrent instances
  never overwrite each other. Counters accepted after the last successful flush
  of a crashed instance are lost: usage can be under-counted by up to one flush
  interval per crash, never over-counted.

  Usage objects live outside `tenants/`, so they survive tenant deletion. Only
  tenants that sent or queried during an hour write objects for it.
  """
  use Pulse.Runtime.GenServer

  alias Pulse.ObjectStore
  alias Pulse.Runtime
  alias Pulse.Runtime.GenServer
  alias Pulse.Storage.S3

  require Logger

  @table __MODULE__
  @signals [:logs, :metrics, :traces]
  @ingest_fields for signal <- @signals, field <- [:requests, :bytes, :records], do: {signal, field}
  @fields @ingest_fields ++ [{:queries, :requests}, {:queries, :duration_ms}]
  @positions @fields |> Enum.with_index(2) |> Map.new()
  @zero List.duplicate(0, length(@fields))
  # Counter rows are `{{tenant, hour}, counter...}`; dirty markers are 1-tuples.
  @row_pattern List.to_tuple([:"$1" | List.duplicate(:_, length(@fields))])
  # Rows per instance, one per active tenant and hour; overflow is dropped
  # and counted rather than growing without bound.
  @max_rows 200_000
  @max_report_objects 10_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  defp table, do: Runtime.table(@table)
  defp config(key, default), do: Keyword.get(Runtime.get_env(:pulse, __MODULE__, []), key, default)

  @doc "Whether this instance meters usage."
  def enabled?, do: config(:enabled, false)

  @doc "Count records of `signal` durably stored for `tenant`."
  def records(signal, tenant, count) when signal in @signals, do: add(tenant, [{{signal, :records}, count}])

  @doc "Count one acknowledged ingest request and its wire bytes."
  def request(signal, tenant, bytes) when signal in @signals,
    do: add(tenant, [{{signal, :requests}, 1}, {{signal, :bytes}, bytes || 0}])

  @doc "Count one query admitted for `tenant` and its wall time."
  def query(tenant, duration_ms), do: add(tenant, [{{:queries, :requests}, 1}, {{:queries, :duration_ms}, duration_ms}])

  defp add(tenant, counts) when is_binary(tenant) do
    # Tenant names become object keys; count only names storage accepts.
    if enabled?() and S3.validate_tenant(tenant) == :ok,
      do: count(table(), {tenant, hour(System.os_time(:second))}, counts)

    :ok
  rescue
    # Not started (some test runtimes and tools): never fail the request.
    ArgumentError -> :ok
  end

  defp add(_tenant, _counts), do: :ok

  defp count(table, key, counts) do
    if :ets.member(table, key) or :ets.info(table, :size) < @max_rows do
      updates = Enum.map(counts, fn {field, n} -> {Map.fetch!(@positions, field), n} end)
      :ets.update_counter(table, key, updates, List.to_tuple([key | @zero]))
      :ets.insert(table, {{:dirty, key}})
    else
      Pulse.SelfMetrics.usage_dropped()
    end
  end

  defp hour(seconds), do: div(seconds, 3600)

  @doc "The `YYYY-MM-DDTHH` label of an hour number (hours since the epoch)."
  def hour_label(hour) do
    {{y, m, d}, {h, _, _}} = :calendar.gregorian_seconds_to_datetime(hour * 3600 + 62_167_219_200)
    :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B", [y, m, d, h]) |> IO.iodata_to_binary()
  end

  @doc "The object key holding `instance`'s usage of `tenant` during `hour`."
  def key(tenant, hour, instance), do: "#{prefix(tenant)}hour=#{hour_label(hour)}/#{instance}.json"

  defp prefix(tenant), do: "usage/v1/tenant=#{tenant}/"

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    :ets.new(table(), [:named_table, :public, :set, write_concurrency: true])
    instance = Keyword.get_lazy(opts, :instance, fn -> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower) end)
    {:ok, %{instance: instance, timer: schedule()}}
  end

  defp schedule, do: Process.send_after(self(), :flush, config(:flush_interval_ms, 60_000))

  @doc false
  # Flush now and wait; for shutdown paths and tests.
  def flush, do: GenServer.call(__MODULE__, :flush, 60_000)

  @impl true
  def handle_call(:flush, _from, state), do: {:reply, flush(state), state}

  @impl true
  def handle_info(:flush, state) do
    flush(state)
    {:noreply, %{state | timer: schedule()}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state), do: flush(state)

  # Take each dirty marker before reading its row: an update after the take
  # marks the row again, so the next flush writes it. Failed writes re-mark.
  defp flush(%{instance: instance}) do
    table = table()

    with {:ok, storage} <- storage_config() do
      dirty = :ets.select(table, [{{{:dirty, :"$1"}}, [], [:"$1"]}])

      failed =
        dirty
        |> Task.async_stream(&write(table, storage, instance, &1), max_concurrency: 8, timeout: :infinity)
        |> Enum.count(&(&1 != {:ok, :ok}))

      if failed > 0, do: Logger.warning("usage flush failed for #{failed} tenant-hours; retrying next interval")
      expire(table)
      if failed == 0, do: :ok, else: {:error, :usage_flush_failed}
    end
  rescue
    ArgumentError -> :ok
  end

  defp write(table, storage, instance, {tenant, hour} = key) do
    :ets.take(table, {:dirty, key})

    case :ets.lookup(table, key) do
      [row] ->
        case ObjectStore.put(storage, key(tenant, hour, instance), encode(row, instance)) do
          {:ok, _etag} ->
            :ok

          {:error, _} = error ->
            :ets.insert(table, {{:dirty, key}})
            error
        end

      [] ->
        :ok
    end
  end

  # Rows of hours before the previous one never change again; once flushed,
  # their objects hold the final totals.
  defp expire(table) do
    current = hour(System.os_time(:second))

    for {_tenant, hour} = key <- :ets.select(table, [{@row_pattern, [], [:"$1"]}]),
        hour < current - 1,
        not :ets.member(table, {:dirty, key}),
        do: :ets.delete(table, key)
  end

  defp storage_config do
    case Runtime.get_env(:pulse, S3) do
      nil -> {:error, :usage_storage_unavailable}
      config -> {:ok, Map.new(config)}
    end
  end

  defp encode(row, instance) do
    [{tenant, hour} | values] = Tuple.to_list(row)
    counts = @fields |> Enum.zip(values) |> group()

    Pulse.JSON.encode!(Map.merge(counts, %{"tenant" => tenant, "hour" => hour_label(hour), "instance" => instance}))
  end

  defp group(pairs) do
    Enum.reduce(pairs, %{}, fn {{group, field}, value}, acc ->
      Map.update(
        acc,
        Atom.to_string(group),
        %{Atom.to_string(field) => value},
        &Map.put(&1, Atom.to_string(field), value)
      )
    end)
  end

  @doc """
  Sum `tenant`'s usage over the hours `from_hour..to_hour` (inclusive, hours
  since the epoch) across every instance. Returns one entry per hour with
  usage, plus the total. Reads at most #{@max_report_objects} objects.
  """
  def report(storage, tenant, from_hour, to_hour) when from_hour <= to_hour do
    with {:ok, keys} <- report_keys(storage, tenant, hour_label(from_hour), hour_label(to_hour)) do
      results =
        keys
        |> Task.async_stream(&fetch(storage, &1), max_concurrency: 8, timeout: :infinity, ordered: false)
        |> Enum.map(fn {:ok, result} -> result end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, summarize(Enum.map(results, fn {:ok, usage} -> usage end))}
        error -> error
      end
    end
  end

  defp report_keys(storage, tenant, from, to) do
    prefix = prefix(tenant)
    collect_keys(storage, prefix, prefix <> "hour=" <> from, to, [])
  end

  defp collect_keys(storage, prefix, cursor, to, acc) do
    case ObjectStore.list_page(storage, prefix, cursor, 1000) do
      {:ok, keys, next} ->
        {within, beyond} = Enum.split_while(keys, &(key_hour(prefix, &1) <= to))
        acc = Enum.reverse(within, acc)

        cond do
          length(acc) > @max_report_objects -> {:error, :usage_range_too_large}
          beyond != [] or is_nil(next) -> {:ok, Enum.reverse(acc)}
          true -> collect_keys(storage, prefix, next, to, acc)
        end

      {:error, _} = error ->
        error
    end
  end

  defp key_hour(prefix, key), do: key |> String.replace_prefix(prefix <> "hour=", "") |> binary_part(0, 13)

  defp fetch(storage, key) do
    with {:ok, body} <- ObjectStore.get(storage, key),
         {:ok, %{"hour" => hour} = usage} <- Pulse.JSON.decode(body) do
      {:ok, {hour, Map.take(usage, Enum.map(@signals ++ [:queries], &Atom.to_string/1))}}
    else
      {:error, :not_found} -> {:ok, nil}
      {:error, _} = error -> error
      _ -> {:error, :usage_object_invalid}
    end
  end

  defp summarize(usages) do
    hours =
      usages
      |> Enum.reject(&is_nil/1)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {hour, counts} -> Map.put(sum(counts), "hour", hour) end)
      |> Enum.sort_by(& &1["hour"])

    %{"hours" => hours, "total" => sum(Enum.map(hours, &Map.delete(&1, "hour")))}
  end

  defp sum(counts) do
    Enum.reduce(counts, zero(), fn usage, acc ->
      Map.new(acc, fn {group, fields} ->
        {group, Map.new(fields, fn {field, value} -> {field, value + (get_in(usage, [group, field]) || 0)} end)}
      end)
    end)
  end

  defp zero, do: @fields |> Enum.map(&{&1, 0}) |> group()
end
