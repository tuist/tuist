defmodule Atlas.Nudges.Workers.RefreshMetricBucketForAccount do
  @moduledoc """
  Refreshes one completed UTC-day bucket of nudge-relevant analytics for
  one account: cache hits/lookups and selective-testing hits/targets.

  Resolves the Atlas account to its Tuist project ids via
  `Atlas.FeatureUsage.Collector.resolve/1`, then runs one ClickHouse scan
  per bucket against `xcode_targets` (`binary_cache_*` and
  `selective_testing_*`). Any failure lands as `refresh_status: "failed"`
  so the evaluator can suppress cleanly.

  Freshness-aware upsert: an incoming refresh only overwrites if its
  `computed_at` is newer than the row it would replace, so a delayed
  manual rerun cannot clobber newer data.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args], states: :incomplete]

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.FeatureUsage.Collector
  alias Atlas.Nudges.Analytics.MetricBucket
  alias Atlas.Repo
  alias Atlas.TuistServer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args}) do
    bucket_date = parse_bucket_date(args["bucket_date"])

    with %Account{} = account <- Repo.get(Account, account_id),
         {:ok, resolution} <- resolve(account) do
      case query_bucket(resolution, bucket_date) do
        {:ok, counters} ->
          upsert_ok(account, bucket_date, counters)

        {:error, reason} ->
          upsert_failed(account, bucket_date, "clickhouse: #{inspect(reason)}")
      end
    else
      nil ->
        {:cancel, :account_not_found}

      {:error, reason} ->
        account = Repo.get(Account, account_id)
        if account, do: upsert_failed(account, bucket_date, "resolve: #{inspect(reason)}")
        :ok
    end
  end

  defp parse_bucket_date(nil), do: Date.utc_today() |> Date.add(-1)
  defp parse_bucket_date(%Date{} = date), do: date

  defp parse_bucket_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> Date.utc_today() |> Date.add(-1)
    end
  end

  defp resolve(%Account{id: account_id}) do
    account_id
    |> account_handles()
    |> Enum.reduce_while({:error, :no_handles}, fn handle, acc ->
      case Collector.resolve(handle) do
        {:ok, %{project_ids: [_ | _]} = resolution} -> {:halt, {:ok, resolution}}
        {:ok, _no_projects} -> {:cont, acc}
        {:error, :not_found} -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, reason}}
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

  defp query_bucket(%{project_ids: project_ids}, %Date{} = bucket_date) do
    day_start = day_start_string(bucket_date)
    day_end = day_start_string(Date.add(bucket_date, 1))

    sql = """
    SELECT
      countIf(binary_cache_hash IS NOT NULL AND binary_cache_hash <> '') AS cache_lookups,
      countIf(binary_cache_hit IN ('local', 'remote')) AS cache_hits,
      countIf(selective_testing_hash IS NOT NULL AND selective_testing_hash <> '') AS selective_targets,
      countIf(selective_testing_hit IN ('local', 'remote')) AS selective_hits
    FROM xcode_targets
    WHERE project_id IN {project_ids:Array(Int64)}
      AND inserted_at >= toDateTime('#{day_start}')
      AND inserted_at <  toDateTime('#{day_end}')
    """

    case TuistServer.clickhouse_query(sql, params: %{"project_ids" => project_ids}, limit: 1) do
      {:ok, %{"rows" => [row | _]}} ->
        {:ok,
         %{
           cache_lookups: to_integer(row["cache_lookups"]),
           cache_hits: to_integer(row["cache_hits"]),
           selective_targets: to_integer(row["selective_targets"]),
           selective_hits: to_integer(row["selective_hits"])
         }}

      {:ok, %{"rows" => []}} ->
        {:ok, %{cache_lookups: 0, cache_hits: 0, selective_targets: 0, selective_hits: 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp day_start_string(%Date{} = date) do
    date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp upsert_ok(%Account{id: account_id}, bucket_date, counters) do
    now = utc_now()
    now_naive = naive_now()

    changeset =
      MetricBucket.changeset(%MetricBucket{}, %{
        account_id: account_id,
        bucket_date: bucket_date,
        daily_cache_hits: counters.cache_hits,
        daily_cache_lookups: counters.cache_lookups,
        daily_selective_hits: counters.selective_hits,
        daily_selective_targets: counters.selective_targets,
        refresh_status: "ok",
        refresh_error: nil,
        computed_at: now
      })

    Repo.insert(
      changeset,
      on_conflict:
        from(b in MetricBucket,
          where: b.computed_at < ^now,
          update: [
            set: [
              daily_cache_hits: ^counters.cache_hits,
              daily_cache_lookups: ^counters.cache_lookups,
              daily_selective_hits: ^counters.selective_hits,
              daily_selective_targets: ^counters.selective_targets,
              refresh_status: "ok",
              refresh_error: nil,
              computed_at: ^now,
              updated_at: ^now_naive
            ]
          ]
        ),
      conflict_target: [:account_id, :bucket_date]
    )
    |> case do
      {:ok, _row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_failed(%Account{id: account_id}, %Date{} = bucket_date, reason) do
    now = utc_now()
    now_naive = naive_now()

    Repo.insert(
      MetricBucket.changeset(%MetricBucket{}, %{
        account_id: account_id,
        bucket_date: bucket_date,
        refresh_status: "failed",
        refresh_error: reason,
        computed_at: now
      }),
      on_conflict:
        from(b in MetricBucket,
          where: b.computed_at < ^now,
          update: [
            set: [
              refresh_status: "failed",
              refresh_error: ^reason,
              computed_at: ^now,
              updated_at: ^now_naive
            ]
          ]
        ),
      conflict_target: [:account_id, :bucket_date]
    )
    |> case do
      {:ok, _row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp naive_now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp to_integer(_value), do: 0
end
