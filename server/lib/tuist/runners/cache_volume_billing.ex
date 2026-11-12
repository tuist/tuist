defmodule Tuist.Runners.CacheVolumeBilling do
  @moduledoc """
  Cache volume storage, billed in GB-months: the first
  `included_byte_months/0` of each billing period are free, and storage past
  that costs $0.10 per GB-month.

  The billable quantity is the saved head of each custom volume over time,
  read from `runner_cache_volume_saved_sizes`. A volume holds one saved head
  however many hosts keep a copy of it, so each logical volume counts once,
  and the size is what the head holds rather than the capacity it was given.
  Retained per-job copies and their measurements are inventory and never
  count. The size is weighted by how long it was held: a head kept for half a
  month counts half as much as one kept for the whole month.

  `docker` and `checkout` volumes are not billed. A head whose size was never
  measured counts as nothing until it is.

  A GB-month is 730 GB-hours, the average length of a month, so the meter's
  unit does not depend on the length of the period it lands in. Usage is
  reported to Stripe in megabyte-months, which a Price with the same tiers as
  the cache egress one (100,000 free, then 0.01 cents each) charges at the
  quoted rate.

  Only reporting and the dashboard read this, never a runner job's path.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Billing
  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes

  @meter_event_name "runner_cache_volume_megabyte_months"

  @bytes_per_gigabyte 1_000_000_000
  @bytes_per_megabyte 1_000_000
  @seconds_per_month 730 * 3600
  @seconds_per_day 86_400

  @included_byte_months 100 * @bytes_per_gigabyte
  @cents_per_gigabyte_month 10

  def meter_event_name, do: @meter_event_name
  def included_byte_months, do: @included_byte_months

  @doc """
  What the storage Price has to charge, in the shape
  `Tuist.Billing.UsagePricing.meter_prices/0` uses.
  """
  def meter_price do
    %{
      event_name: @meter_event_name,
      included: div(@included_byte_months, @bytes_per_megabyte),
      cents: @cents_per_gigabyte_month,
      per_units: div(@bytes_per_gigabyte, @bytes_per_megabyte)
    }
  end

  @doc """
  The whole megabyte-months `account_id` stored over `[period_start, period_end)`,
  which is what Stripe is sent.
  """
  def meter_value(account_id, %DateTime{} = period_start, %DateTime{} = period_end) when is_integer(account_id) do
    account_id
    |> byte_seconds_per_day(period_start, period_end)
    |> Enum.map(& &1.byte_seconds)
    |> Enum.sum()
    |> div(@bytes_per_megabyte * @seconds_per_month)
  end

  @doc """
  Saved bytes held over `[period_start, period_end)`, multiplied by the
  seconds they were held, per UTC day and repository.

  Returns `%{date, repository, byte_seconds}` rows. Each volume's size at
  `period_start` is the latest observation before it, and each later
  observation holds until the next one.
  """
  def byte_seconds_per_day(account_id, %DateTime{} = period_start, %DateTime{} = period_end) do
    if DateTime.before?(period_start, period_end) do
      %{rows: rows} =
        Repo.query!(
          """
          WITH volumes AS (
            SELECT id, repository FROM runner_cache_volumes
            WHERE account_id = $1 AND key <> ALL($4::text[])
          ),
          observations AS (
            SELECT v.id AS volume_id, v.repository, $2::timestamptz AS observed_at, b.id, b.size_bytes
            FROM volumes v
            JOIN LATERAL (
              SELECT id, size_bytes FROM runner_cache_volume_saved_sizes
              WHERE volume_id = v.id AND observed_at <= $2
              ORDER BY observed_at DESC, id DESC LIMIT 1
            ) b ON true
            UNION ALL
            SELECT v.id, v.repository, s.observed_at, s.id, s.size_bytes
            FROM volumes v
            JOIN runner_cache_volume_saved_sizes s ON s.volume_id = v.id
            WHERE s.observed_at > $2 AND s.observed_at < $3
          ),
          intervals AS (
            SELECT repository, size_bytes, observed_at AS starts_at,
              LEAD(observed_at, 1, $3::timestamptz) OVER (PARTITION BY volume_id ORDER BY observed_at, id) AS ends_at
            FROM observations
          ),
          days AS (
            SELECT generate_series(date_trunc('day', $2::timestamptz, 'UTC'), $3::timestamptz, interval '24 hours') AS starts_at
          )
          SELECT (d.starts_at AT TIME ZONE 'UTC')::date, i.repository,
            SUM(i.size_bytes::numeric * EXTRACT(EPOCH FROM
              LEAST(i.ends_at, d.starts_at + interval '24 hours') - GREATEST(i.starts_at, d.starts_at)))
          FROM intervals i
          JOIN days d ON i.starts_at < d.starts_at + interval '24 hours' AND i.ends_at > d.starts_at
          WHERE i.size_bytes > 0 AND i.ends_at > i.starts_at
          GROUP BY 1, 2
          ORDER BY 1, 2
          """,
          [account_id, period_start, period_end, CacheVolumes.unbilled_keys()]
        )

      Enum.map(rows, fn [date, repository, byte_seconds] ->
        %{date: date, repository: repository, byte_seconds: to_integer(byte_seconds)}
      end)
    else
      []
    end
  end

  @doc """
  The saved bytes `account_id` holds at `at`.
  """
  def stored_bytes(account_id, %DateTime{} = at) do
    %{rows: [[bytes]]} =
      Repo.query!(
        """
        SELECT COALESCE(SUM(s.size_bytes), 0)
        FROM runner_cache_volumes v
        JOIN LATERAL (
          SELECT size_bytes FROM runner_cache_volume_saved_sizes
          WHERE volume_id = v.id AND observed_at <= $2
          ORDER BY observed_at DESC, id DESC LIMIT 1
        ) s ON true
        WHERE v.account_id = $1 AND v.key <> ALL($3::text[])
        """,
        [account_id, at, CacheVolumes.unbilled_keys()]
      )

    to_integer(bytes)
  end

  @doc """
  The period's storage, what it is worth, and what a runner trial and the
  allowance take off it. Quantities are byte-months, so they format as bytes
  and read as GB-months.

  A runner trial is the absence of runner items on the subscription, the
  storage item included, so storage during a trial is not billed and does not
  spend the allowance. `billed` is only set for an account with a subscription
  to bill against.

  Saved-size history is kept for `CacheVolumes.saved_size_retention_days/0`,
  so a period that starts before then has `history_complete: false` and no
  figures.
  """
  def period_breakdown(%Account{} = account, {%DateTime{} = period_start, %DateTime{} = period_end}) do
    now = DateTime.utc_now()
    usage_end = if DateTime.before?(now, period_end), do: now, else: period_end
    history_start = DateTime.add(now, -CacheVolumes.saved_size_retention_days(), :day)

    base = %{
      period_start: DateTime.to_date(period_start),
      period_end: DateTime.to_date(period_end),
      usage_through: DateTime.to_date(usage_end),
      included: @included_byte_months,
      history_complete: not DateTime.before?(period_start, history_start)
    }

    if base.history_complete do
      Map.merge(base, breakdown(account, period_start, period_end, usage_end))
    else
      base
    end
  end

  defp breakdown(account, period_start, period_end, usage_end) do
    rows = byte_seconds_per_day(account.id, period_start, usage_end)
    stored = stored_bytes(account.id, usage_end)
    open? = DateTime.before?(usage_end, period_end)

    gross = rows |> Enum.map(& &1.byte_seconds) |> Enum.sum() |> div(@seconds_per_month)
    trial = trial_byte_months(account, period_start, usage_end)
    billable = max(gross - trial - @included_byte_months, 0)
    charge = cost(billable)
    subscribed = not is_nil(Billing.get_current_active_subscription(account))

    %{
      byte_months: gross,
      stored_bytes: stored,
      projected: if(open?, do: gross + div(stored * DateTime.diff(period_end, usage_end, :second), @seconds_per_month)),
      trial_covered: trial,
      billable: billable,
      gross: cost(gross),
      trial_credit: Money.subtract(cost(gross), cost(gross - trial)),
      included_credit: Money.subtract(cost(gross - trial), charge),
      charge: charge,
      billed: if(subscribed, do: charge),
      days: days(rows, period_start, usage_end),
      projected_days: if(open?, do: projected_days(stored, usage_end, period_end), else: [])
    }
  end

  # Average bytes held on each day, over the part of the day the period
  # covers, so today's bar is not shrunk by the hours it has not reached yet.
  defp days(rows, period_start, usage_end) do
    Enum.map(rows, fn row ->
      day_start = DateTime.new!(row.date, ~T[00:00:00.000000], "Etc/UTC")
      from = latest(day_start, period_start)
      to = earliest(DateTime.add(day_start, @seconds_per_day, :second), usage_end)

      %{date: row.date, repository: row.repository, bytes: div(row.byte_seconds, max(DateTime.diff(to, from), 1))}
    end)
  end

  # The days the period has not reached, at what is saved now: storage stays
  # until a volume is cleared or expires, so today's size is the forecast.
  defp projected_days(0, _usage_end, _period_end), do: []

  defp projected_days(stored, usage_end, period_end) do
    first = usage_end |> DateTime.to_date() |> Date.add(1)
    last = period_end |> DateTime.add(-1, :microsecond) |> DateTime.to_date()

    if Date.after?(first, last), do: [], else: Enum.map(Date.range(first, last), &%{date: &1, bytes: stored})
  end

  # See `Tuist.Runners.Allowance` for why a restarted trial reads only its
  # latest interval.
  defp trial_byte_months(%Account{runner_trial_started_at: nil}, _period_start, _usage_end), do: 0

  defp trial_byte_months(%Account{} = account, period_start, usage_end) do
    from = latest(account.runner_trial_started_at, period_start)
    to = earliest(account.runner_trial_ended_at || usage_end, usage_end)

    account.id
    |> byte_seconds_per_day(from, to)
    |> Enum.map(& &1.byte_seconds)
    |> Enum.sum()
    |> div(@seconds_per_month)
  end

  defp cost(byte_months), do: Money.new(div(byte_months * @cents_per_gigabyte_month, @bytes_per_gigabyte), :USD)

  defp latest(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
  defp earliest(a, b), do: if(DateTime.before?(a, b), do: a, else: b)

  defp to_integer(%Decimal{} = decimal), do: decimal |> Decimal.round(0, :down) |> Decimal.to_integer()
  defp to_integer(value) when is_integer(value), do: value
end
