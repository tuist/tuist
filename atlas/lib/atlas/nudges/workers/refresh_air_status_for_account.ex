defmodule Atlas.Nudges.Workers.RefreshAirStatusForAccount do
  @moduledoc """
  Refreshes one account's Air (`runner_minutes`) notification status for
  the current billing period.

  `air_usage_notifications` lives on the Tuist server. One row per
  (recipient, threshold), so we collapse to `count(DISTINCT threshold)`
  server-side. Any resolution or query failure is persisted as
  `refresh_status: "failed"` so the enterprise-fit signal can suppress
  cleanly.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args], states: :incomplete]

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.FeatureUsage.Collector
  alias Atlas.Nudges.Analytics.AirStatus
  alias Atlas.Repo
  alias Atlas.TuistServer

  @metric "runner_minutes"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    with %Account{} = account <- Repo.get(Account, account_id),
         {:ok, resolution} <- resolve(account) do
      case query_air_status(resolution.account_id) do
        {:ok, %{period_start: nil}} ->
          :ok

        {:ok, status} ->
          upsert_ok(account, status)

        {:error, reason} ->
          upsert_failed(account, "clickhouse: #{inspect(reason)}")
      end
    else
      nil ->
        {:cancel, :account_not_found}

      {:error, reason} ->
        account = Repo.get(Account, account_id)
        if account, do: upsert_failed(account, "resolve: #{inspect(reason)}")
        :ok
    end
  end

  defp resolve(%Account{id: account_id}) do
    account_id
    |> account_handles()
    |> Enum.reduce_while({:error, :no_handles}, fn handle, acc ->
      case Collector.resolve(handle) do
        {:ok, %{account_id: tuist_account_id} = resolution}
        when is_integer(tuist_account_id) ->
          {:halt, {:ok, resolution}}

        {:ok, _partial} ->
          {:cont, acc}

        {:error, :not_found} ->
          {:cont, acc}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp account_handles(account_id) do
    AccountHandle
    |> where([h], h.account_id == ^account_id)
    |> order_by([h], asc: h.inserted_at)
    |> select([h], h.handle)
    |> Repo.all()
  end

  defp query_air_status(tuist_account_id) when is_integer(tuist_account_id) do
    sql = """
    SELECT period_start,
           count(DISTINCT threshold) AS distinct_thresholds_delivered,
           min(delivered_at) AS first_crossed_at
    FROM air_usage_notifications
    WHERE account_id = #{tuist_account_id}
      AND metric = '#{@metric}'
      AND delivered_at IS NOT NULL
    GROUP BY period_start
    ORDER BY period_start DESC
    LIMIT 1
    """

    case TuistServer.query(sql, limit: 1) do
      {:ok, %{"rows" => [row | _]}} ->
        {:ok,
         %{
           period_start: parse_date(row["period_start"]),
           distinct_thresholds_delivered: to_integer(row["distinct_thresholds_delivered"]),
           first_crossed_at: parse_datetime(row["first_crossed_at"])
         }}

      {:ok, %{"rows" => []}} ->
        {:ok, %{period_start: nil, distinct_thresholds_delivered: 0, first_crossed_at: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_ok(%Account{id: account_id}, status) do
    now = utc_now()

    Repo.insert(
      AirStatus.changeset(%AirStatus{}, %{
        account_id: account_id,
        period_start: status.period_start,
        metric: @metric,
        distinct_thresholds_delivered: status.distinct_thresholds_delivered,
        first_crossed_at: status.first_crossed_at,
        refresh_status: "ok",
        refresh_error: nil,
        computed_at: now
      }),
      on_conflict: [
        set: [
          distinct_thresholds_delivered: status.distinct_thresholds_delivered,
          first_crossed_at: status.first_crossed_at,
          refresh_status: "ok",
          refresh_error: nil,
          computed_at: now,
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        ]
      ],
      conflict_target: [:account_id, :period_start, :metric]
    )
    |> case do
      {:ok, _row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_failed(%Account{id: account_id}, reason) do
    now = utc_now()
    period = Date.utc_today() |> Date.beginning_of_month()

    Repo.insert(
      AirStatus.changeset(%AirStatus{}, %{
        account_id: account_id,
        period_start: period,
        metric: @metric,
        refresh_status: "failed",
        refresh_error: reason,
        computed_at: now
      }),
      on_conflict: [
        set: [
          refresh_status: "failed",
          refresh_error: reason,
          computed_at: now,
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        ]
      ],
      conflict_target: [:account_id, :period_start, :metric]
    )
    |> case do
      {:ok, _row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt |> DateTime.truncate(:second)

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp to_integer(_value), do: 0
end
