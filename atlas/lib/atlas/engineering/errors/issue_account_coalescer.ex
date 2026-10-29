defmodule Atlas.Engineering.Errors.IssueAccountCoalescer do
  @moduledoc """
  Coalesces per-(issue, account) counter bumps so ingest can attribute
  events to Atlas CRM accounts without a synchronous Postgres roundtrip.

  Same pattern as `Atlas.Engineering.Errors.IssueCoalescer`: observations
  are cast into an in-memory accumulator keyed by `{issue_id, account_id}`
  and every flush interval the accumulator is written back as a single
  `INSERT ... ON CONFLICT DO UPDATE`. Counter bumps are additive;
  first_seen folds via LEAST, last_seen via GREATEST.

  Handle resolution happens in `Atlas.Accounts.HandleRegistry`; this
  module only accepts an already-resolved `account_id`. That keeps the
  DB roundtrip off the ingest hot path (registry hits `:persistent_term`)
  and keeps the write budget to one upsert per flush window rather than
  one per event.

  Rows that fail to upsert (unlikely: FK violation only if the issue
  or account was concurrently deleted) get dropped with a log, matching
  the drop-on-flush-failure behaviour of the sibling coalescer.
  """

  use GenServer

  import Ecto.Query

  alias Atlas.Engineering.Errors.IssueAccount
  alias Atlas.Repo

  require Logger

  @flush_interval_ms :timer.seconds(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Records that `issue_id` was observed impacting `account_id` at
  `timestamp`. Non-blocking cast.
  """
  def observe(server \\ __MODULE__, issue_id, account_id, %DateTime{} = timestamp)
      when is_binary(issue_id) and is_binary(account_id) do
    GenServer.cast(server, {:observe, issue_id, account_id, timestamp})
  end

  @doc """
  Forces an immediate flush. Test + shutdown use only.
  """
  def flush(server \\ __MODULE__) do
    GenServer.call(server, :flush, :infinity)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    interval = Keyword.get(opts, :flush_interval_ms, @flush_interval_ms)
    timer = Process.send_after(self(), :tick, interval)
    {:ok, %{accumulator: %{}, timer: timer, interval: interval}}
  end

  @impl true
  def handle_cast({:observe, issue_id, account_id, timestamp}, state) do
    ts = force_usec(timestamp)
    key = {issue_id, account_id}
    entry = Map.get(state.accumulator, key)
    updated = merge_observation(entry, issue_id, account_id, ts)
    {:noreply, %{state | accumulator: Map.put(state.accumulator, key, updated)}}
  end

  @impl true
  def handle_info(:tick, state) do
    do_flush(state.accumulator)
    timer = Process.send_after(self(), :tick, state.interval)
    {:noreply, %{state | accumulator: %{}, timer: timer}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    Process.cancel_timer(state.timer)
    do_flush(state.accumulator)
    timer = Process.send_after(self(), :tick, state.interval)
    {:reply, :ok, %{state | accumulator: %{}, timer: timer}}
  end

  @impl true
  def terminate(_reason, %{accumulator: accumulator}), do: do_flush(accumulator)

  defp merge_observation(nil, issue_id, account_id, ts) do
    %{issue_id: issue_id, account_id: account_id, count: 1, first_seen: ts, last_seen: ts}
  end

  defp merge_observation(entry, _issue_id, _account_id, ts) do
    %{entry | count: entry.count + 1, first_seen: min_dt(entry.first_seen, ts), last_seen: max_dt(entry.last_seen, ts)}
  end

  defp min_dt(a, b), do: if(DateTime.before?(a, b), do: a, else: b)
  defp max_dt(a, b), do: if(DateTime.after?(a, b), do: a, else: b)

  defp force_usec(%DateTime{microsecond: {_, 6}} = dt), do: dt
  defp force_usec(%DateTime{microsecond: {value, _}} = dt), do: %{dt | microsecond: {value, 6}}

  defp do_flush(accumulator) when map_size(accumulator) == 0, do: :ok

  defp do_flush(accumulator) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    rows = accumulator |> Map.values() |> Enum.map(&row_for_upsert(&1, now))

    try do
      Repo.insert_all(
        IssueAccount,
        rows,
        on_conflict: on_conflict_query(),
        conflict_target: [:issue_id, :account_id]
      )

      :ok
    rescue
      error ->
        Logger.warning(
          "issue_account_coalescer: flush failed for #{map_size(accumulator)} pair(s): #{Exception.message(error)}"
        )

        :ok
    end
  end

  defp row_for_upsert(entry, now) do
    %{
      id: Ecto.UUID.generate(),
      issue_id: entry.issue_id,
      account_id: entry.account_id,
      event_count: entry.count,
      first_seen: entry.first_seen,
      last_seen: entry.last_seen,
      inserted_at: now,
      updated_at: now
    }
  end

  defp on_conflict_query do
    from existing in IssueAccount,
      update: [
        set: [
          event_count: fragment("? + EXCLUDED.event_count", existing.event_count),
          first_seen: fragment("LEAST(?, EXCLUDED.first_seen)", existing.first_seen),
          last_seen: fragment("GREATEST(?, EXCLUDED.last_seen)", existing.last_seen),
          updated_at: fragment("CURRENT_TIMESTAMP")
        ]
      ]
  end
end
