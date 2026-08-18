defmodule Tuist.Runners.BillingTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Billing
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.RunnerSession

  # Billing measures the job window, not the Pod window. Most cases here
  # only care about the interval maths, so the job window defaults to the
  # Pod window; a test that cares about the difference passes
  # `job_started_at` / `job_ended_at` (or nil) explicitly.
  defp session_fixture(account, attrs) do
    attrs = Map.new(attrs)

    defaults = %{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "fleet-a",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      started_at: nil,
      ended_at: nil,
      job_started_at: Map.get(attrs, :started_at),
      job_ended_at: Map.get(attrs, :ended_at),
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    Repo.insert!(struct(RunnerSession, Map.merge(defaults, attrs)))
  end

  describe "compute_milliseconds/3" do
    test "sums billable runtime across multiple closed sessions" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      session_fixture(account,
        started_at: ~U[2026-05-10 12:00:00.000000Z],
        ended_at: ~U[2026-05-10 12:05:00.000000Z]
      )

      session_fixture(account,
        started_at: ~U[2026-05-15 09:00:00.000000Z],
        ended_at: ~U[2026-05-15 09:10:00.000000Z]
      )

      # 5 minutes + 10 minutes = 15 minutes = 900_000 ms
      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 900_000
    end

    test "only counts the intersection for sessions that cross the window boundary" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      # Session spans April → May. Only the May portion should
      # bill against this window.
      session_fixture(account,
        started_at: ~U[2026-04-30 23:00:00.000000Z],
        ended_at: ~U[2026-05-01 01:00:00.000000Z]
      )

      # 1 hour into the window from 00:00 → 01:00 May 1st.
      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 60 * 60 * 1_000
    end

    test "bills nothing for a job still in flight" do
      account = account_fixture()
      now = DateTime.utc_now()
      period_start = DateTime.add(now, -1, :day)
      period_end = DateTime.add(now, 30, :day)

      # Pod claimed 5 minutes ago, job still running: no completion
      # webhook has landed, so there is no evidenced window yet.
      session_fixture(account,
        started_at: DateTime.add(now, -5, :minute),
        ended_at: nil,
        job_started_at: nil,
        job_ended_at: nil
      )

      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 0
    end

    test "bills nothing when the Pod ran but no job window was ever recorded" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      # A completed Pod whose `workflow_job.completed` webhook never
      # arrived. The Pod's wall clock is not evidence the customer's
      # work ran, so it bills nothing rather than falling back to it.
      session_fixture(account,
        started_at: ~U[2026-05-10 12:00:00.000000Z],
        ended_at: ~U[2026-05-10 12:30:00.000000Z],
        job_started_at: nil,
        job_ended_at: nil
      )

      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 0
    end

    test "bills the job window, not the Pod's boot and teardown around it" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      # Pod held the host for 20 minutes; the customer's job ran for 5
      # of them. The other 15 are VM boot and teardown, which are ours.
      session_fixture(account,
        started_at: ~U[2026-05-10 12:00:00.000000Z],
        ended_at: ~U[2026-05-10 12:20:00.000000Z],
        job_started_at: ~U[2026-05-10 12:10:00.000000Z],
        job_ended_at: ~U[2026-05-10 12:15:00.000000Z]
      )

      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 5 * 60 * 1_000
    end

    test "excludes sessions that ended before the window" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      session_fixture(account,
        started_at: ~U[2026-04-20 09:00:00.000000Z],
        ended_at: ~U[2026-04-20 09:05:00.000000Z]
      )

      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 0
    end

    test "scopes results to the requested account" do
      mine = account_fixture()
      other = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      session_fixture(mine,
        started_at: ~U[2026-05-10 12:00:00.000000Z],
        ended_at: ~U[2026-05-10 12:05:00.000000Z]
      )

      session_fixture(other,
        started_at: ~U[2026-05-10 12:00:00.000000Z],
        ended_at: ~U[2026-05-10 12:15:00.000000Z]
      )

      assert Billing.compute_milliseconds(mine.id, period_start, period_end) == 5 * 60 * 1_000
    end

    test "an orphaned Pod cannot run away with the bill" do
      account = account_fixture()
      now = DateTime.utc_now()

      # Pod opened 12 hours ago and never closed (lost `stopped`
      # event). Under the Pod-clock window this needed a six-hour
      # safety clamp; billing the job window makes it structurally
      # impossible, because no job window was ever recorded.
      session_fixture(account,
        started_at: DateTime.add(now, -12, :hour),
        ended_at: nil,
        job_started_at: nil,
        job_ended_at: nil
      )

      period_start = DateTime.add(now, -1, :day)
      period_end = DateTime.add(now, 1, :day)

      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 0
    end

    test "retries bill for every Pod the customer actually held" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      # Same workflow_job, two Pod lifecycles — the first
      # released after 3 minutes, the second ran a full 8.
      session_fixture(account,
        workflow_job_id: 50_001,
        started_at: ~U[2026-05-10 09:00:00.000000Z],
        ended_at: ~U[2026-05-10 09:03:00.000000Z]
      )

      session_fixture(account,
        workflow_job_id: 50_001,
        started_at: ~U[2026-05-10 09:05:00.000000Z],
        ended_at: ~U[2026-05-10 09:13:00.000000Z]
      )

      assert Billing.compute_milliseconds(account.id, period_start, period_end) == 11 * 60 * 1_000
    end
  end

  describe "compute_milliseconds_by_machine/4" do
    test "groups usage by platform and machine specification" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-02 00:00:00.000000Z]

      session_fixture(account,
        fleet_name: "linux-first",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        started_at: ~U[2026-05-01 10:00:00.000000Z],
        ended_at: ~U[2026-05-01 10:05:00.000000Z]
      )

      session_fixture(account,
        fleet_name: "linux-second",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        started_at: ~U[2026-05-01 11:00:00.000000Z],
        ended_at: ~U[2026-05-01 11:10:00.000000Z]
      )

      session_fixture(account,
        fleet_name: "macos-xcode-26-5",
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        started_at: ~U[2026-05-01 12:00:00.000000Z],
        ended_at: ~U[2026-05-01 12:07:00.000000Z]
      )

      assert [
               %{platform: :linux, vcpus: 2, memory_gb: 8, total_ms: 900_000},
               %{platform: :macos, vcpus: 6, memory_gb: 14, total_ms: 420_000}
             ] = Billing.compute_milliseconds_by_machine(account.id, period_start, period_end)
    end

    test "falls back to the fleet catalog for historical sessions" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-02 00:00:00.000000Z]

      session_fixture(account,
        fleet_name: Catalog.pool_name(%{platform: :linux, vcpus: 2, memory_gb: 8}),
        started_at: ~U[2026-05-01 10:00:00.000000Z],
        ended_at: ~U[2026-05-01 10:03:00.000000Z]
      )

      assert [%{platform: :linux, vcpus: 2, memory_gb: 8, total_ms: 180_000}] =
               Billing.compute_milliseconds_by_machine(account.id, period_start, period_end)
    end
  end

  describe "meter_event_name/1" do
    test "is one compute-unit meter per platform" do
      assert Billing.meter_event_name(:linux) == "runner_linux_compute_unit_milliseconds"
      assert Billing.meter_event_name(:macos) == "runner_macos_compute_unit_milliseconds"
    end
  end

  describe "compute_units_by_platform/4" do
    test "weights each machine by its multiplier and totals per platform" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-02 00:00:00.000000Z]

      # Baseline shape: one compute-unit millisecond per elapsed millisecond.
      session_fixture(account,
        fleet_name: "linux-baseline",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        billing_multiplier: Catalog.billing_multiplier(:linux, 2, 8),
        started_at: ~U[2026-05-01 10:00:00.000000Z],
        ended_at: ~U[2026-05-01 10:05:00.000000Z]
      )

      # Twice the baseline shape, so the same wall-clock time is worth twice
      # as many units.
      session_fixture(account,
        fleet_name: "linux-double",
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        billing_multiplier: Catalog.billing_multiplier(:linux, 4, 16),
        started_at: ~U[2026-05-01 11:00:00.000000Z],
        ended_at: ~U[2026-05-01 11:05:00.000000Z]
      )

      # The macOS baseline machine, which is one macOS unit per elapsed
      # millisecond and totals into its own meter rather than the Linux one.
      session_fixture(account,
        fleet_name: "macos-standard",
        platform: :macos,
        vcpus: 6,
        memory_gb: 14,
        billing_multiplier: Catalog.billing_multiplier(:macos, 6, 14),
        started_at: ~U[2026-05-01 12:00:00.000000Z],
        ended_at: ~U[2026-05-01 12:05:00.000000Z]
      )

      assert Billing.compute_units_by_platform(account.id, period_start, period_end) == [
               %{platform: :linux, total_units: 300_000 + 2 * 300_000},
               %{platform: :macos, total_units: 300_000}
             ]
    end

    test "bills a session at the multiplier it was admitted under, not the current catalog" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-02 00:00:00.000000Z]

      # Half the weighting the catalog would give this shape today, standing
      # in for a session opened under an older rate card.
      session_fixture(account,
        fleet_name: "linux-legacy-rate-card",
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        billing_multiplier: div(Catalog.billing_multiplier(:linux, 4, 16), 2),
        started_at: ~U[2026-05-01 10:00:00.000000Z],
        ended_at: ~U[2026-05-01 10:05:00.000000Z]
      )

      assert Billing.compute_units_by_platform(account.id, period_start, period_end) == [
               %{platform: :linux, total_units: 300_000}
             ]
    end

    test "falls back to the catalog multiplier for sessions that never stored one" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-02 00:00:00.000000Z]

      session_fixture(account,
        fleet_name: "linux-pre-multiplier",
        platform: :linux,
        vcpus: 4,
        memory_gb: 16,
        started_at: ~U[2026-05-01 10:00:00.000000Z],
        ended_at: ~U[2026-05-01 10:05:00.000000Z]
      )

      assert Billing.compute_units_by_platform(account.id, period_start, period_end) == [
               %{platform: :linux, total_units: 600_000}
             ]
    end
  end

  describe "compute_minutes/2" do
    test "returns the widget shape with total_ms, trend, dates, values" do
      account = account_fixture()
      now = DateTime.utc_now()

      session_fixture(account,
        started_at: DateTime.add(now, -2, :hour),
        ended_at: now |> DateTime.add(-2, :hour) |> DateTime.add(15, :minute)
      )

      result =
        Billing.compute_minutes(account.id,
          start_datetime: DateTime.add(now, -1, :day),
          end_datetime: now
        )

      assert is_integer(result.total_ms)
      assert_in_delta result.total_ms, 15 * 60 * 1_000, 1_000
      assert is_float(result.trend)
      assert is_list(result.dates)
      assert is_list(result.values)
      assert length(result.dates) == length(result.values)
      # 15 minutes lands on the bucket(s) holding the session.
      # `values` is integer minutes per bucket — when the session
      # spans an hour boundary, each bucket's milliseconds are
      # truncated independently via `div(60_000)`, so the sum can
      # lose up to 1 minute to per-bucket rounding. `total_ms`
      # (asserted above) is the source of truth.
      assert Enum.sum(result.values) in 14..15
    end

    test "filters by :repository scope" do
      account = account_fixture()
      now = DateTime.utc_now()

      session_fixture(account,
        repository: "acme/server",
        started_at: DateTime.add(now, -1, :hour),
        ended_at: now |> DateTime.add(-1, :hour) |> DateTime.add(10, :minute)
      )

      session_fixture(account,
        repository: "acme/cli",
        started_at: DateTime.add(now, -1, :hour),
        ended_at: now |> DateTime.add(-1, :hour) |> DateTime.add(20, :minute)
      )

      scoped =
        Billing.compute_minutes(account.id,
          start_datetime: DateTime.add(now, -1, :day),
          end_datetime: now,
          repository: "acme/server"
        )

      assert_in_delta scoped.total_ms, 10 * 60 * 1_000, 1_000
    end

    test "filters by :platform via fleet_name prefix" do
      account = account_fixture()
      now = DateTime.utc_now()

      session_fixture(account,
        fleet_name: "macos-large",
        started_at: DateTime.add(now, -1, :hour),
        ended_at: now |> DateTime.add(-1, :hour) |> DateTime.add(5, :minute)
      )

      session_fixture(account,
        fleet_name: "linux-amd64",
        started_at: DateTime.add(now, -1, :hour),
        ended_at: now |> DateTime.add(-1, :hour) |> DateTime.add(7, :minute)
      )

      mac =
        Billing.compute_minutes(account.id,
          start_datetime: DateTime.add(now, -1, :day),
          end_datetime: now,
          platform: "macos"
        )

      linux =
        Billing.compute_minutes(account.id,
          start_datetime: DateTime.add(now, -1, :day),
          end_datetime: now,
          platform: "linux"
        )

      assert_in_delta mac.total_ms, 5 * 60 * 1_000, 1_000
      assert_in_delta linux.total_ms, 7 * 60 * 1_000, 1_000
    end
  end

  describe "compute_milliseconds_per_bucket/5" do
    test "buckets a single session into its UTC day" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      session_fixture(account,
        started_at: ~U[2026-05-10 12:00:00.000000Z],
        ended_at: ~U[2026-05-10 12:05:00.000000Z]
      )

      result = Billing.compute_milliseconds_per_bucket(account.id, period_start, period_end, :day)

      assert Map.get(result, ~D[2026-05-10]) == 5 * 60 * 1_000
    end

    test "splits a midnight-spanning session across the two affected days" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      Repo.query!("SET LOCAL TIME ZONE 'Europe/Berlin'")

      # 23:50 May 10 → 00:10 May 11 = 20 minutes total. 10 mins
      # belong to May 10, 10 mins to May 11.
      session_fixture(account,
        started_at: ~U[2026-05-10 23:50:00.000000Z],
        ended_at: ~U[2026-05-11 00:10:00.000000Z]
      )

      result = Billing.compute_milliseconds_per_bucket(account.id, period_start, period_end, :day)

      assert_in_delta Map.get(result, ~D[2026-05-10]), 10 * 60 * 1_000, 1_000
      assert_in_delta Map.get(result, ~D[2026-05-11]), 10 * 60 * 1_000, 1_000
    end

    test "hour bucket splits a session crossing the hour boundary" do
      account = account_fixture()
      period_start = ~U[2026-05-10 00:00:00.000000Z]
      period_end = ~U[2026-05-11 00:00:00.000000Z]

      # 12:50 → 13:10 = 20 minutes total. 10 min in 12:00, 10 in 13:00.
      session_fixture(account,
        started_at: ~U[2026-05-10 12:50:00.000000Z],
        ended_at: ~U[2026-05-10 13:10:00.000000Z]
      )

      result = Billing.compute_milliseconds_per_bucket(account.id, period_start, period_end, :hour)

      assert_in_delta Map.get(result, ~U[2026-05-10 12:00:00.000000Z]), 10 * 60 * 1_000, 1_000
      assert_in_delta Map.get(result, ~U[2026-05-10 13:00:00.000000Z]), 10 * 60 * 1_000, 1_000
    end
  end
end
