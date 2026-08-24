defmodule Tuist.Runners.Billing do
  @moduledoc """
  Billing-grade compute-time aggregation over `runner_sessions`.

  Each row in `runner_sessions` is a Pod lifecycle — `started_at`
  on claim-win, `ended_at` on completion webhook (or `NULL` for
  Pods still in flight). Invoicing reads from here, never from
  `runner_jobs`. See the migration's @moduledoc for the
  architectural rationale.

  ## Window semantics

  Billing measures the workflow job, not the Pod. A session's
  `started_at` / `ended_at` bound the Pod: it boots a VM before the
  job can start and holds the host through post-job cache work and
  teardown afterwards. That overhead is ours to optimize, so the
  billable window is GitHub's own `job_started_at` / `job_ended_at`,
  recorded on the session when the completion webhook arrives.

  `compute_milliseconds/3` returns the sum of *interval
  intersections* between each session's job window and the billing
  window `[period_start, period_end]`:

      max(0, min(job_ended_at, period_end) - max(job_started_at, period_start))

  That treats cross-boundary jobs correctly — a job that ran for two
  hours across a month boundary contributes only the minutes that
  fall on each side. It's also retry-safe: each re-claim creates a
  new session row, so a workflow_job that was released and re-served
  bills for each execution.

  ## Sessions without a job window

  A session bills nothing until both job bounds are recorded. That
  covers an in-flight job, a job cancelled while still queued (it
  never ran), and a Pod whose completion webhook never arrived. A
  missing window is not evidence of execution, so charging nothing
  is the honest answer and keeps the module's bias toward
  undercharging. It also removes the orphaned-Pod runaway the
  Pod-clock window needed a six-hour safety clamp to bound: an
  unreported job simply has no billable time.

  The trade-off is that a currently-running job contributes zero
  until it completes, so a mid-period usage figure lags by whatever
  is still in flight.

  ## Precision

  The math is in milliseconds end-to-end; rendering to minutes
  or hours happens at the formatting boundary. Daily series use
  the same interval-intersection but bucketed per UTC day, so a
  session that spans midnight contributes to both days.

  ## Stripe reporting

  Usage is metered as normalized compute units, one Stripe meter per
  platform. Each platform is normalized to its own baseline machine,
  so one Linux compute unit is one minute on the 2 vCPU / 8 GB Linux
  baseline and one macOS compute unit is one minute on the 6 vCPU /
  14 GB Mac. A session's elapsed milliseconds are scaled by the
  multiplier frozen on the row when it opened. Each meter receives
  compute-unit milliseconds and its price transforms 60,000 units
  into one billed baseline-minute, so a platform's Price is quoted
  directly per baseline machine-minute.

  Per platform rather than per exact shape: Stripe caps classic
  subscriptions at 20 items, and a per-shape catalog would burn one
  item per shape plus a Meter, Price, config key, and backfill for
  every shape ever added. Two meters keep a subscription at two
  runner items no matter how many shapes the catalog grows to, while
  leaving each platform's rate, credit grants, discounts, contract
  terms, and invoice line items independently movable in Stripe. A
  single global unit would instead fix both platforms' rates to one
  hardcoded ratio. Raw shape, raw milliseconds, and the frozen
  multiplier stay on the row, so analytics lose nothing.

  Usage is always reported gross. Prepaid runner access is a
  money-denominated Stripe billing credit grant scoped to the runner
  meter prices, rather than minutes subtracted in Tuist. Scoping a
  grant to one platform's Price is what lets prepaid terms differ
  between Linux and macOS.
  """

  import Ecto.Query
  import Tuist.Runners.Catalog, only: [valid_machine_resources: 3]

  alias Tuist.Repo
  alias Tuist.Runners.Analytics
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.RunnerSession

  require Logger

  @default_window_days 30

  @doc """
  Total billable minutes for `account_id` over the window, plus a
  per-bucket series + trend versus the previous equivalent window.
  The underlying source is `runner_sessions` — the same number that
  invoicing will charge against.

  Options:

    * `:start_datetime` / `:end_datetime` — window. Defaults to
      the last 30 days.
    * `:repository`, `:workflow_name` — exact-match scope filters.
    * `:platform` — `"macos"` or `"linux"`, narrows on the
      `fleet_name` prefix.

  Returns `%{total_ms, trend, dates, values}` where `values` are
  whole minutes per bucket (truncated for display; precision is
  preserved in `total_ms`).
  """
  def compute_minutes(account_id, opts \\ []) when is_integer(account_id) do
    {start_dt, end_dt} = window(opts)
    {prev_start_dt, prev_end_dt} = previous_window(start_dt, end_dt)
    bucket = bucket_opt(opts, start_dt, end_dt)

    total_ms = compute_milliseconds(account_id, start_dt, end_dt, opts)
    previous_total_ms = compute_milliseconds(account_id, prev_start_dt, prev_end_dt, opts)

    per_bucket = compute_milliseconds_per_bucket(account_id, start_dt, end_dt, bucket, opts)

    filled =
      start_dt
      |> bucket_range(end_dt, bucket)
      |> Enum.map(fn date ->
        ms = Map.get(per_bucket, date, 0)
        %{date: date, value: ms |> div(60_000) |> trunc()}
      end)

    %{
      total_ms: total_ms,
      trend: trend(previous_total_ms, total_ms),
      dates: Enum.map(filled, & &1.date),
      values: Enum.map(filled, & &1.value)
    }
  end

  @doc """
  Total billable compute-unit milliseconds for `account_id` over
  `[period_start, period_end]`. Each Pod session contributes only
  the portion of its runtime that lies inside the window.

  Compute units, not elapsed time: this is the quantity Stripe is
  metered on, so a machine on a 2x multiplier contributes twice its
  wall-clock milliseconds. An allowance or a dashboard reading elapsed
  time would let that machine consume half the allowance it should and
  read as half its real cost.

  Accepts the same scope opts (`:repository`, `:workflow_name`,
  `:platform`) as `compute_minutes/2` so a filtered query and a
  filtered invoice line up against the same shape.
  """
  def compute_milliseconds(account_id, %DateTime{} = period_start, %DateTime{} = period_end, opts \\ [])
      when is_integer(account_id) do
    account_id
    |> compute_units_by_platform(period_start, period_end, opts)
    |> Enum.map(& &1.total_units)
    |> Enum.sum()
  end

  @doc """
  Returns billable milliseconds grouped by immutable machine
  specification for the requested window, each entry carrying the
  effective `billing_multiplier` that machine was admitted under.

  New sessions persist their resource selection and multiplier
  directly. Rows created during the rollout can have neither; those
  fall back to the fleet catalog. An unresolvable historical fleet is
  omitted with a warning so billing remains biased toward
  undercharging.
  """
  def compute_milliseconds_by_machine(account_id, %DateTime{} = period_start, %DateTime{} = period_end, opts \\ [])
      when is_integer(account_id) do
    account_id
    |> sessions_overlapping(period_start, period_end)
    |> scope(opts)
    |> group_by([s], [s.fleet_name, s.platform, s.vcpus, s.memory_gb, s.billing_multiplier])
    |> select([s], %{
      fleet_name: s.fleet_name,
      platform: s.platform,
      vcpus: s.vcpus,
      memory_gb: s.memory_gb,
      billing_multiplier: s.billing_multiplier,
      total_ms:
        fragment(
          """
          COALESCE(SUM(GREATEST(
            0,
            (EXTRACT(EPOCH FROM (
              LEAST(?, ?) - GREATEST(?, ?)
            )) * 1000)::bigint
          )), 0)::bigint
          """,
          s.job_ended_at,
          ^period_end,
          s.job_started_at,
          ^period_start
        )
    })
    |> Repo.all()
    |> Enum.reduce(%{}, &merge_machine_usage/2)
    |> Enum.map(fn {{platform, vcpus, memory_gb, multiplier}, total_ms} ->
      %{
        platform: platform,
        vcpus: vcpus,
        memory_gb: memory_gb,
        billing_multiplier: multiplier,
        total_ms: total_ms
      }
    end)
    |> Enum.sort_by(&{&1.platform, &1.vcpus, &1.memory_gb, &1.billing_multiplier})
  end

  @doc """
  Billable compute-unit milliseconds grouped by platform for the
  requested window.

  This is what Stripe is metered on. Each machine group's elapsed
  milliseconds are scaled by the multiplier frozen on its sessions, so a
  4 vCPU / 16 GB Linux machine contributes twice the units of the Linux
  baseline for the same wall-clock time. Because each platform is
  normalized to its own baseline machine, one macOS compute unit is one
  minute on the real 6 vCPU / 14 GB Mac, and its Stripe Price is quoted
  directly in those terms.

  One meter per platform, rather than one per exact shape, keeps a
  subscription at two runner items no matter how many shapes the catalog
  grows to, while leaving each platform's rate, credit grants, and
  contract terms independently movable in Stripe.

  Weighted milliseconds truncate rather than round, keeping the same
  under-bill bias the rest of this module holds to.
  """
  def compute_units_by_platform(account_id, %DateTime{} = period_start, %DateTime{} = period_end, opts \\ [])
      when is_integer(account_id) do
    account_id
    |> compute_milliseconds_by_machine(period_start, period_end, opts)
    |> Enum.reduce(%{}, fn usage, acc ->
      Map.update(acc, usage.platform, compute_units(usage), &(&1 + compute_units(usage)))
    end)
    |> Enum.map(fn {platform, total_units} -> %{platform: platform, total_units: total_units} end)
    |> Enum.sort_by(& &1.platform)
  end

  defp compute_units(%{total_ms: total_ms, billing_multiplier: multiplier}) do
    div(total_ms * multiplier, Catalog.compute_unit_basis_points())
  end

  @doc """
  Stable Stripe meter event name for a runner platform.
  """
  def meter_event_name(platform) when platform in [:linux, :macos] do
    "runner_#{platform}_compute_unit_milliseconds"
  end

  @doc """
  Returns a bucket-keyed map of billable compute-unit milliseconds within the
  window. Sessions crossing a bucket boundary contribute to each
  bucket they overlap. `bucket` is `:hour` (`%{DateTime.t() =>
  integer_ms}`) or `:day` (`%{Date.t() => integer_ms}`).

  Used to drive the per-bucket series chart on the billing/jobs
  pages. The caller can format the values however they want
  (minutes, hours, dollars) at render time.
  """
  def compute_milliseconds_per_bucket(
        account_id,
        %DateTime{} = period_start,
        %DateTime{} = period_end,
        bucket,
        opts \\ []
      )
      when is_integer(account_id) and bucket in [:hour, :day] do
    # SQL pipeline:
    #   1. `overlapping` — sessions for this account whose window
    #      touches [period_start, period_end] (CTE).
    #   2. `buckets` — explode each session into one row per bucket
    #      (UTC day, or hour) it overlaps using `generate_series`.
    #   3. Outer SELECT — per-bucket SUM of the intersection between
    #      (session, bucket, billing-period), grouped by machine so the
    #      multiplier can be applied per shape. All interval math in
    #      Postgres, so a busy window doesn't materialise thousands of
    #      rows into the BEAM.
    overlapping =
      account_id
      |> sessions_overlapping(period_start, period_end)
      |> scope(opts)
      |> select([s], %{
        started_at: s.job_started_at,
        effective_end: s.job_ended_at,
        fleet_name: s.fleet_name,
        platform: s.platform,
        vcpus: s.vcpus,
        memory_gb: s.memory_gb,
        billing_multiplier: s.billing_multiplier
      })

    buckets = buckets_query(overlapping, period_start, period_end, bucket)

    from(b in subquery(buckets),
      group_by: [b.day, b.fleet_name, b.platform, b.vcpus, b.memory_gb, b.billing_multiplier],
      select: %{
        day: b.day,
        fleet_name: b.fleet_name,
        platform: b.platform,
        vcpus: b.vcpus,
        memory_gb: b.memory_gb,
        billing_multiplier: b.billing_multiplier,
        total_ms: fragment("SUM(?)::bigint", b.intersection_ms)
      }
    )
    |> Repo.all()
    |> weigh_by(& &1.day)
  end

  # Elapsed milliseconds become the compute units Stripe is metered on:
  # scaled by the multiplier the machine was admitted under, resolved the
  # same way `compute_milliseconds_by_machine/4` resolves it so an
  # aggregate can never disagree with the invoice. Grouping happens in
  # Postgres; only the per-shape weighting is done here, because the
  # multiplier for a session that never recorded one comes from the
  # catalog rather than the row.
  defp weigh_by(rows, key_fun) do
    Enum.reduce(rows, %{}, fn row, acc ->
      case resources_for_session(row) do
        {:ok, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb}} ->
          multiplier = multiplier_for_session(row, platform, vcpus, memory_gb)
          units = div(row.total_ms * multiplier, Catalog.compute_unit_basis_points())
          Map.update(acc, key_fun.(row), units, &(&1 + units))

        {:error, :invalid_resources} ->
          Logger.warning(
            "runners: omitting #{row.total_ms} billing milliseconds with unknown resources for fleet #{row.fleet_name}"
          )

          acc
      end
    end)
  end

  @doc """
  Billable compute-unit milliseconds per day, split by the repository
  whose workflow ran them.

  Repository rather than project: a runner session records the
  repository that triggered the job and nothing else, so that is the
  finest attribution the data supports without inventing a mapping.
  """
  def compute_milliseconds_per_repository(account_id, %DateTime{} = period_start, %DateTime{} = period_end)
      when is_integer(account_id) do
    overlapping =
      account_id
      |> sessions_overlapping(period_start, period_end)
      |> select([s], %{
        started_at: s.job_started_at,
        effective_end: s.job_ended_at,
        repository: s.repository,
        fleet_name: s.fleet_name,
        platform: s.platform,
        vcpus: s.vcpus,
        memory_gb: s.memory_gb,
        billing_multiplier: s.billing_multiplier
      })

    from(b in subquery(repository_buckets_query(overlapping, period_start, period_end)),
      group_by: [b.day, b.repository, b.fleet_name, b.platform, b.vcpus, b.memory_gb, b.billing_multiplier],
      select: %{
        day: b.day,
        repository: b.repository,
        fleet_name: b.fleet_name,
        platform: b.platform,
        vcpus: b.vcpus,
        memory_gb: b.memory_gb,
        billing_multiplier: b.billing_multiplier,
        total_ms: fragment("SUM(?)::bigint", b.intersection_ms)
      }
    )
    |> Repo.all()
    |> weigh_by(&{&1.day, &1.repository})
    |> Enum.map(fn {{day, repository}, units} -> %{date: day, repository: repository, total_ms: units} end)
    |> Enum.sort_by(&{Date.to_erl(&1.date), &1.repository})
  end

  defp repository_buckets_query(overlapping, period_start, period_end) do
    from(o in subquery(overlapping),
      inner_lateral_join:
        bucket in fragment(
          """
          (SELECT generate_series(
            (GREATEST(?, ?::timestamptz) AT TIME ZONE 'UTC')::date,
            (LEAST(?, ?::timestamptz) AT TIME ZONE 'UTC')::date,
            '1 day'::interval
          )::date AS day)
          """,
          o.started_at,
          ^period_start,
          o.effective_end,
          ^period_end
        ),
      on: true,
      select: %{
        day: bucket.day,
        repository: o.repository,
        fleet_name: o.fleet_name,
        platform: o.platform,
        vcpus: o.vcpus,
        memory_gb: o.memory_gb,
        billing_multiplier: o.billing_multiplier,
        intersection_ms:
          fragment(
            """
            GREATEST(0, (EXTRACT(EPOCH FROM (
              LEAST(?, (?::date + INTERVAL '1 day') AT TIME ZONE 'UTC', ?) -
              GREATEST(?, ?::date::timestamp AT TIME ZONE 'UTC', ?)
            )) * 1000)::bigint)
            """,
            o.effective_end,
            bucket.day,
            ^period_end,
            o.started_at,
            bucket.day,
            ^period_start
          )
      }
    )
  end

  defp buckets_query(overlapping, period_start, period_end, :day) do
    from(o in subquery(overlapping),
      inner_lateral_join:
        bucket in fragment(
          """
          (SELECT generate_series(
            (GREATEST(?, ?::timestamptz) AT TIME ZONE 'UTC')::date,
            (LEAST(?, ?::timestamptz) AT TIME ZONE 'UTC')::date,
            '1 day'::interval
          )::date AS day)
          """,
          o.started_at,
          ^period_start,
          o.effective_end,
          ^period_end
        ),
      on: true,
      select: %{
        day: bucket.day,
        fleet_name: o.fleet_name,
        platform: o.platform,
        vcpus: o.vcpus,
        memory_gb: o.memory_gb,
        billing_multiplier: o.billing_multiplier,
        intersection_ms:
          fragment(
            """
            GREATEST(0, (EXTRACT(EPOCH FROM (
              LEAST(?, (?::date + INTERVAL '1 day') AT TIME ZONE 'UTC', ?) -
              GREATEST(?, ?::date::timestamp AT TIME ZONE 'UTC', ?)
            )) * 1000)::bigint)
            """,
            o.effective_end,
            bucket.day,
            ^period_end,
            o.started_at,
            bucket.day,
            ^period_start
          )
      }
    )
  end

  defp buckets_query(overlapping, period_start, period_end, :hour) do
    from(o in subquery(overlapping),
      inner_lateral_join:
        bucket in fragment(
          """
          (SELECT generate_series(
            date_trunc('hour', GREATEST(?, ?::timestamptz)),
            date_trunc('hour', LEAST(?, ?::timestamptz)),
            '1 hour'::interval
          ) AS day)
          """,
          o.started_at,
          ^period_start,
          o.effective_end,
          ^period_end
        ),
      on: true,
      select: %{
        day: bucket.day,
        fleet_name: o.fleet_name,
        platform: o.platform,
        vcpus: o.vcpus,
        memory_gb: o.memory_gb,
        billing_multiplier: o.billing_multiplier,
        intersection_ms:
          fragment(
            """
            GREATEST(0, (EXTRACT(EPOCH FROM (
              LEAST(?, ? + INTERVAL '1 hour', ?) -
              GREATEST(?, ?, ?)
            )) * 1000)::bigint)
            """,
            o.effective_end,
            bucket.day,
            ^period_end,
            o.started_at,
            bucket.day,
            ^period_start
          )
      }
    )
  end

  # Only sessions carrying a complete job window are billable, and the
  # overlap is tested against that window rather than the Pod's. A
  # session whose job never ran, or whose completion webhook never
  # arrived, has NULL bounds and is excluded entirely: we bill nothing
  # we cannot evidence rather than falling back to the Pod's wall clock.
  defp sessions_overlapping(account_id, period_start, period_end) do
    from(s in RunnerSession,
      where: s.account_id == ^account_id,
      where: not is_nil(s.job_started_at) and not is_nil(s.job_ended_at),
      where: s.job_started_at <= ^period_end,
      where: s.job_ended_at >= ^period_start
    )
  end

  defp merge_machine_usage(row, usage) do
    case resources_for_session(row) do
      {:ok, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb}} ->
        multiplier = multiplier_for_session(row, platform, vcpus, memory_gb)
        Map.update(usage, {platform, vcpus, memory_gb, multiplier}, row.total_ms, &(&1 + row.total_ms))

      {:error, :invalid_resources} ->
        Logger.warning(
          "runners: omitting #{row.total_ms} billing milliseconds with unknown resources for fleet #{row.fleet_name}"
        )

        usage
    end
  end

  defp resources_for_session(%{platform: platform, vcpus: vcpus, memory_gb: memory_gb})
       when valid_machine_resources(platform, vcpus, memory_gb) do
    {:ok, %{platform: platform, vcpus: vcpus, memory_gb: memory_gb}}
  end

  defp resources_for_session(%{fleet_name: fleet_name}), do: Catalog.resources_for_fleet(fleet_name)

  # Sessions opened before the multiplier was persisted fall back to the
  # current catalog weighting. That is the one case where a rate-card
  # change can move an old session's price, and it is unavoidable: those
  # rows never recorded what they were admitted under.
  defp multiplier_for_session(%{billing_multiplier: multiplier}, _platform, _vcpus, _memory_gb)
       when is_integer(multiplier) and multiplier > 0, do: multiplier

  defp multiplier_for_session(_row, platform, vcpus, memory_gb),
    do: Catalog.billing_multiplier(platform, vcpus, memory_gb)

  defp scope(query, opts) do
    query
    |> maybe_eq(:repository, Keyword.get(opts, :repository))
    |> maybe_eq(:workflow_name, Keyword.get(opts, :workflow_name))
    |> maybe_platform(Keyword.get(opts, :platform))
  end

  defp maybe_eq(query, _field, nil), do: query
  defp maybe_eq(query, _field, ""), do: query
  defp maybe_eq(query, _field, "any"), do: query

  defp maybe_eq(query, :repository, value) when is_binary(value), do: where(query, [s], s.repository == ^value)

  defp maybe_eq(query, :workflow_name, value) when is_binary(value), do: where(query, [s], s.workflow_name == ^value)

  # Platform filter narrows on the `fleet_name` prefix. Each
  # platform's `Catalog.fleet_name_prefixes/1` returns both the legacy
  # `<platform>-…` per-env pool prefix and the catalog-derived
  # `<runners_<platform>_pool_name_prefix>-…` prefix, so profile-
  # dispatched and legacy jobs surface together under the right
  # filter bucket.
  defp maybe_platform(query, nil), do: query
  defp maybe_platform(query, ""), do: query
  defp maybe_platform(query, "any"), do: query

  defp maybe_platform(query, "linux"), do: filter_by_prefixes(query, Catalog.fleet_name_prefixes(:linux))

  defp maybe_platform(query, "macos"), do: filter_by_prefixes(query, Catalog.fleet_name_prefixes(:macos))

  defp maybe_platform(query, _), do: query

  # OR `starts_with(fleet_name, prefix)` across every prefix as a
  # single `where`. `or_where` would OR against the *whole* prior
  # chain (account scope, time window, etc.), wiping them out; the
  # dynamic stays nested inside the surrounding ANDs.
  defp filter_by_prefixes(query, [first | rest]) do
    predicate =
      Enum.reduce(rest, dynamic([s], fragment("starts_with(?, ?)", s.fleet_name, ^first)), fn prefix, acc ->
        dynamic([s], ^acc or fragment("starts_with(?, ?)", s.fleet_name, ^prefix))
      end)

    where(query, ^predicate)
  end

  defp window(opts) do
    end_dt = Keyword.get(opts, :end_datetime, DateTime.utc_now())

    start_dt =
      Keyword.get(opts, :start_datetime, DateTime.add(end_dt, -@default_window_days, :day))

    {start_dt, end_dt}
  end

  defp previous_window(start_dt, end_dt) do
    delta_seconds = DateTime.diff(end_dt, start_dt, :second)
    {DateTime.add(start_dt, -delta_seconds, :second), start_dt}
  end

  defp bucket_range(%DateTime{} = start_dt, %DateTime{} = end_dt, :day) do
    Date.range(DateTime.to_date(start_dt), DateTime.to_date(end_dt))
  end

  defp bucket_range(%DateTime{} = start_dt, %DateTime{} = end_dt, :hour) do
    # Microsecond precision matches Postgres `date_trunc('hour', …)`
    # output (`{0, 6}`) so the DateTime keys are structurally equal
    # when used as map lookups against `compute_milliseconds_per_bucket`.
    floor_start = %{start_dt | minute: 0, second: 0, microsecond: {0, 6}}
    floor_end = %{end_dt | minute: 0, second: 0, microsecond: {0, 6}}

    floor_start
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, floor_end) != :gt))
  end

  defp bucket_opt(opts, start_dt, end_dt) do
    case Keyword.get(opts, :bucket) do
      bucket when bucket in [:hour, :day] -> bucket
      _ -> Analytics.bucket_for_window(start_dt, end_dt)
    end
  end

  defp trend(previous, current) when is_number(previous) and is_number(current) do
    cond do
      previous == 0 -> 0.0
      current == 0 -> 0.0
      true -> Float.round(current / previous * 100, 1) - 100.0
    end
  end

  defp trend(_, _), do: 0.0
end
