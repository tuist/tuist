defmodule Tuist.Kura.Usage do
  @moduledoc """
  Persists and queries Kura node usage rollups.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Identity
  alias Tuist.Kura.UsageEvent
  alias Tuist.Projects

  @max_events_per_batch 5_000

  @doc """
  Persists usage rollups from managed nodes. Each is attributed to the account
  named by `tenant_id` and to that account's project named by `namespace_id`,
  whatever the casing of either handle. Anything that does not resolve lands on 0
  and is treated as unattributable traffic.
  """
  def create_events(events) when is_list(events) and length(events) <= @max_events_per_batch do
    account_ids_by_handle = events |> Enum.map(& &1["tenant_id"]) |> Identity.account_ids()
    result = insert_events(events, &Map.get(account_ids_by_handle, &1["tenant_id"], 0), trust_origin: true)
    record_managed_demand(events, account_ids_by_handle)
    result
  end

  def create_events(events) when is_list(events), do: {:error, :too_many_events}

  @doc """
  Persists usage rollups from a self-hosted node, attributed to the `account` its
  credential authenticated as. Origins are dropped: placement reads them as
  evidence about hosted regions, which a self-hosted node does not speak for.
  """
  def create_events(events, %Account{id: account_id}) when is_list(events) and length(events) <= @max_events_per_batch do
    insert_events(events, fn _event -> account_id end, trust_origin: false)
  end

  def create_events(events, %Account{}) when is_list(events), do: {:error, :too_many_events}

  # Only trusted managed-node traffic refreshes hosted capacity. Replayed old
  # rollups, replication, storage snapshots and self-hosted reports do not.
  # This is the traffic clock's main source: bytes a client actually moved.
  defp record_managed_demand(events, account_ids) do
    now = System.system_time(:second)

    events
    |> Enum.filter(fn event ->
      started = event["window_start_unix_seconds"]
      count = event["request_count"]

      event["traffic_plane"] == "public" and is_integer(count) and count > 0 and
        is_integer(started) and started >= now - 300 and started <= now + 30
    end)
    |> Enum.map(&Map.get(account_ids, &1["tenant_id"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(&Demand.record(&1, nil, traffic: true))
  end

  defp insert_events(events, account_id_for, trust_origin: trust_origin?) do
    attributed = Enum.map(events, &{&1, account_id_for.(&1)})

    project_ids =
      attributed
      |> Enum.flat_map(fn
        {%{"namespace_id" => namespace}, account_id} when account_id != 0 and is_binary(namespace) ->
          [{account_id, namespace}]

        _unattributed ->
          []
      end)
      |> Projects.project_ids_by_account_and_handle()

    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    rows =
      Enum.map(attributed, fn {event, account_id} ->
        event = if trust_origin?, do: event, else: Map.delete(event, "origin")
        build_row(event, account_id, project_ids, now)
      end)

    if rows != [] do
      IngestRepo.insert_all(UsageEvent, rows)
    end

    {:ok, length(rows)}
  end

  defp build_row(event, account_id, project_ids, now) do
    %{
      event_id: event["event_id"],
      account_id: account_id,
      project_id: Map.get(project_ids, {account_id, event["namespace_id"]}, 0),
      node_id: event["node_id"],
      region: event["region"],
      traffic_plane: event["traffic_plane"],
      direction: event["direction"],
      operation: event["operation"],
      protocol: event["protocol"],
      artifact_kind: event["artifact_kind"],
      bytes: event["bytes"],
      request_count: event["request_count"],
      origin: origin(event["origin"]),
      window_start: unix_seconds_to_naive_datetime(event["window_start_unix_seconds"]),
      window_seconds: event["window_seconds"],
      inserted_at: now
    }
  end

  # A label a node read off a credential the control plane signed, checked for
  # shape here as well so nothing else reaches a column placement groups on.
  defp origin(origin) when is_binary(origin) do
    if origin =~ ~r/\A[A-Z]{2}(-[A-Z0-9]{1,3})?\z/, do: origin, else: ""
  end

  defp origin(_origin), do: ""

  defp unix_seconds_to_naive_datetime(seconds) when is_integer(seconds) do
    seconds
    |> DateTime.from_unix!()
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
  end

  @doc """
  Total deduped request count per account over the trailing `days`
  window, for every account in `account_ids`. Used by
  `Tuist.Kura.Rollouts` to order accounts into waves by recent usage
  ascending; accounts with no usage are absent from the result and read
  as zero.
  """
  def recent_request_counts_by_account(account_ids, days \\ 7)

  def recent_request_counts_by_account([], _days), do: %{}

  def recent_request_counts_by_account(account_ids, days) when is_list(account_ids) do
    cutoff =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-days * 86_400, :second)
      |> NaiveDateTime.truncate(:second)

    deduped =
      from(e in UsageEvent,
        where: e.account_id in ^account_ids and e.window_start >= ^cutoff,
        group_by: [e.account_id, e.event_id],
        select: %{
          account_id: e.account_id,
          request_count: fragment("argMax(?, ?)", e.request_count, e.inserted_at)
        }
      )

    from(e in subquery(deduped),
      group_by: e.account_id,
      select: {e.account_id, fragment("sum(?)", e.request_count)}
    )
    |> ClickHouseRepo.all()
    |> Map.new(fn {account_id, count} -> {account_id, zeroed(count)} end)
  end

  defp zeroed(nil), do: 0
  defp zeroed(%Decimal{} = d), do: Decimal.to_integer(d)
  defp zeroed(n) when is_integer(n), do: n
  defp zeroed(n) when is_float(n), do: trunc(n)
end
