defmodule Tuist.Kura.Demand do
  @moduledoc """
  Records and reads Kura cache demand for an account-region instance.

  Cache demand is any authenticated Xcode, Module, or Gradle cache read or
  write that would route to Kura. General project activity, command events
  unrelated to cache, billing events, and dashboard visits do not count, which
  is why demand is recorded at the request boundary — cache-endpoint
  resolution, where a client asks where to send cache traffic — rather than
  derived after the fact from analytics tables. Endpoint resolution covers all
  three lanes uniformly and is the same call for a developer machine and for a
  runner build.

  That boundary is a hot path, so `record/1` never touches the database. It
  writes the account id into an ETS buffer; a periodic flush resolves each
  distinct account's effective plan and service region once and upserts the
  demand timestamps in a single statement. Demand is buffered by account, not
  by account-region, so the hot path never has to resolve a region: one Kura
  instance serves the account in its service region, and the flush is where
  that region is looked up.

  Losing a flush window to a crash costs at most that window's worth of
  recency on a clock measured in days, so the buffer is deliberately not
  durable.
  """
  use GenServer

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionLifecycle
  alias Tuist.Repo

  @table __MODULE__
  @flush_interval to_timeout(minute: 1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Buffers cache demand for an account. Safe to call from any request; it is a
  single ETS write and never fails, including before the buffer has started.

  Configured to write through the repo instead of buffering, the write lands
  in the caller's connection. Tests run that way (`config/test.exs`, matching
  `Tuist.Ingestion.Bufferable`) so a process-wide buffer cannot carry one
  test's demand into another's transaction.
  """
  def record(account_id) when is_integer(account_id) do
    if Environment.kura_demand_write_through_repo?() do
      persist([{account_id, System.system_time(:second)}])
      :ok
    else
      :ets.insert(@table, {account_id, System.system_time(:second)})
      :ok
    end
  rescue
    ArgumentError -> :ok
  end

  def record(_account_id), do: :ok

  @doc """
  Drains the buffer into `kura_account_region_lifecycles`. Called on the flush
  timer, and directly by the archival sweep so a demand recorded moments
  earlier is never read as absence.

  The drain runs in the calling process rather than in the buffer: the table
  is public and `:ets.take/2` is atomic, so concurrent flushes are safe, and
  the writes stay in the caller's transaction and connection.
  """
  def flush do
    if Environment.kura_demand_write_through_repo?(), do: {:ok, 0}, else: drain()
  end

  @doc """
  The lifecycle row for an account-region, or `nil` when the account has never
  asked for Kura cache in that region.
  """
  def get(account_id, service_region) do
    Repo.get_by(AccountRegionLifecycle, account_id: account_id, service_region: service_region)
  end

  @doc """
  True when the account is under the demand-driven lifecycle in any region.

  Cache-endpoint resolution uses this to decide what to answer while no Kura
  instance is serving: a lifecycle-managed account falls back to authoritative
  object storage, because falling back to the account's legacy custom endpoints
  would make archival the thing that keeps the legacy path alive.
  """
  def lifecycle_managed?(%Account{id: account_id}) do
    Repo.exists?(from(l in AccountRegionLifecycle, where: l.account_id == ^account_id))
  end

  @doc """
  Upserts demand for one account-region, keeping the latest timestamp. Used by
  the backfill, which resolves regions from historical analytics rather than
  from the buffer.
  """
  def upsert(account_id, service_region, %DateTime{} = demand_at) do
    upsert_all([%{account_id: account_id, service_region: service_region, last_cache_demand_at: demand_at}])
  end

  @doc """
  Sets or clears the keep-warm exception for an account-region. A keep-warm
  instance is never drained and never counted as archival-eligible; it holds
  its full allocation while inactive.
  """
  def set_keep_warm(account_id, service_region, keep_warm?) when is_boolean(keep_warm?) do
    case get(account_id, service_region) do
      nil ->
        {:error, :not_found}

      %AccountRegionLifecycle{} = lifecycle ->
        lifecycle
        |> AccountRegionLifecycle.keep_warm_changeset(%{keep_warm: keep_warm?})
        |> Repo.update()
    end
  end

  @impl GenServer
  def init(opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    interval = Keyword.get(opts, :flush_interval, @flush_interval)
    schedule_flush(interval)
    {:ok, %{flush_interval: interval}}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    drain()
    schedule_flush(state.flush_interval)
    {:noreply, state}
  end

  defp schedule_flush(interval), do: Process.send_after(self(), :flush, interval)

  # `:ets.take/2` reads and removes each key atomically, so a `record/1`
  # racing the drain either lands before the take (and is persisted) or after
  # it (and survives for the next flush). Nothing is dropped in between.
  defp drain do
    @table
    |> :ets.select([{{:"$1", :_}, [], [:"$1"]}])
    |> Enum.flat_map(&:ets.take(@table, &1))
    |> persist()
  end

  defp persist(entries) do
    entries
    |> rows_for()
    |> upsert_all()
  end

  defp rows_for([]), do: []

  defp rows_for(entries) do
    demand_at_by_account =
      Map.new(entries, fn {account_id, recorded_at} ->
        {account_id, DateTime.from_unix!(recorded_at)}
      end)

    demand_at_by_account
    |> Map.keys()
    |> accounts_with_subscriptions()
    |> Enum.flat_map(fn account ->
      case AccountPolicies.resolve(account) do
        {:ok, %{service_region: service_region}} ->
          [
            %{
              account_id: account.id,
              service_region: service_region,
              last_cache_demand_at: Map.fetch!(demand_at_by_account, account.id)
            }
          ]

        # An account whose plan or region cannot be resolved has no
        # account-region instance to keep warm, so there is nothing to record.
        # It keeps being served by authoritative object storage.
        {:error, _reason} ->
          []
      end
    end)
  end

  defp accounts_with_subscriptions(account_ids) do
    Repo.all(
      from(a in Account,
        where: a.id in ^account_ids,
        preload: [:subscriptions]
      )
    )
  end

  defp upsert_all([]), do: {:ok, 0}

  defp upsert_all(rows) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      Enum.map(rows, fn row ->
        row
        |> Map.put(:id, UUIDv7.generate())
        |> Map.update!(:last_cache_demand_at, &DateTime.truncate(&1, :second))
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    {count, _} =
      Repo.insert_all(AccountRegionLifecycle, rows,
        conflict_target: [:account_id, :service_region],
        on_conflict:
          from(l in AccountRegionLifecycle,
            update: [
              set: [
                last_cache_demand_at: fragment("GREATEST(?, EXCLUDED.last_cache_demand_at)", l.last_cache_demand_at),
                updated_at: fragment("EXCLUDED.updated_at")
              ]
            ]
          )
      )

    {:ok, count}
  end
end
