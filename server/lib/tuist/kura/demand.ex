defmodule Tuist.Kura.Demand do
  @moduledoc """
  Records and reads Kura cache demand for an account-region instance.

  Demand is recorded at the request boundary: cache-endpoint resolution, where
  a client asks where to send cache traffic. That covers the Xcode, Module, and
  Gradle lanes uniformly, is the same call for a developer machine and for a
  runner build, and is the only signal available when an account has no
  instance at all — which is what lets an archived account ask for one back
  rather than deadlocking. General project activity, command events unrelated
  to cache, billing events, and dashboard visits never reach here.

  It is deliberately a proxy for cache traffic rather than a measure of it, and
  it errs in both directions. `tuist setup cache` installs a LaunchAgent with
  `RunAtLoad`, so the cache daemon resolves an endpoint on every login: an
  account whose agent is installed but idle keeps refreshing its clock without
  anyone building, and may never reach a full inactive window. In the other
  direction the CLI caches a resolved endpoint for an hour, so most requests
  during a build never reach here at all.

  Both are accepted. Holding an idle account warm is the safe error, and the
  alternative — keeping the clock on `kura_usage_events`, which the instances
  push for real transfers, while endpoint resolution only triggers provisioning
  — needs two signals to say what one says now, against a clock measured in
  days. Fleet sizing should read the archival population as a floor rather than
  an estimate because of it.

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
  instance is serving: a lifecycle-managed account falls back to the
  Tuist-hosted default lane rather than to its own legacy custom endpoints,
  because routing archived accounts at the custom-endpoint path would make
  archival the thing that keeps that path alive.
  """
  def lifecycle_managed?(%Account{id: account_id}) do
    Repo.exists?(from(l in AccountRegionLifecycle, where: l.account_id == ^account_id))
  end

  @doc """
  Whether a Kura instance is expected to start serving for this account
  shortly, so a client should treat an endpoint answer as short-lived.

  True whenever the account resolves to a service region, which is checked
  only where no Kura endpoint is being served. That is deliberately broader
  than "an instance row already exists": the request asking this question is
  itself the one that records the demand a cold return is provisioned from, so
  on the first request after an archive there is no row yet and a narrower
  check would report `false` on the one request where the answer matters most,
  leaving the client caching a stand-in lane for its full interval.

  The cost is that an account the region keeps refusing for capacity reports
  `true` for as long as that lasts, and re-resolves every 30 seconds. That is
  accepted: a region with no room is an operational problem to be alerted on
  and fixed by adding a machine, not a steady state to design around. The
  `capacity_refused` counter is the signal for it.
  """
  def instance_expected?(%Account{} = account) do
    match?({:ok, _resolution}, AccountPolicies.resolve(account))
  end

  @doc """
  Upserts demand for one account-region, keeping the latest timestamp. Used by
  the backfill, which resolves regions from historical analytics rather than
  from the buffer.
  """
  def upsert(account_id, service_region, %DateTime{} = demand_at) do
    upsert_many([%{account_id: account_id, service_region: service_region, last_cache_demand_at: demand_at}])
  end

  @doc """
  Upserts a batch of account-region demand rows in one statement, keeping the
  latest timestamp per row. The backfill seeds thousands of rows at once, so it
  goes through here rather than paying a round trip each.

  Rows are `%{account_id:, service_region:, last_cache_demand_at:}`.
  """
  def upsert_many(rows) when is_list(rows), do: upsert_all(rows)

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
        # It keeps being served by whatever lane it is on today.
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
