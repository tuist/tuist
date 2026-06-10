defmodule Tuist.Runners.BillingTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Billing
  alias Tuist.Runners.RunnerSession

  defp session_fixture(account, attrs) do
    defaults = %{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "fleet-a",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      started_at: nil,
      ended_at: nil,
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    Repo.insert!(struct(RunnerSession, Map.merge(defaults, Map.new(attrs))))
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

    test "open sessions clamp to now() when period_end is in the future" do
      account = account_fixture()
      now = DateTime.utc_now()
      period_start = DateTime.add(now, -1, :day)
      period_end = DateTime.add(now, 30, :day)

      # Session started 5 minutes ago with no ended_at. Billing
      # bills started_at → now(), not forever.
      session_fixture(account,
        started_at: DateTime.add(now, -5, :minute),
        ended_at: nil
      )

      result = Billing.compute_milliseconds(account.id, period_start, period_end)

      # 5 minutes ± a generous tolerance for clock drift between
      # the fixture insert and the billing query.
      assert_in_delta result, 5 * 60 * 1_000, 2_000
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

    test "caps an open session at the max-lifetime safety clamp (6 hours)" do
      account = account_fixture()
      now = DateTime.utc_now()

      # Session opened 12 hours ago, never closed (lost `stopped`
      # event). Without the clamp this would bill 12 hours; with
      # the clamp it bills at most 6 hours.
      session_fixture(account,
        started_at: DateTime.add(now, -12, :hour),
        ended_at: nil
      )

      period_start = DateTime.add(now, -1, :day)
      period_end = DateTime.add(now, 1, :day)

      ms = Billing.compute_milliseconds(account.id, period_start, period_end)
      six_hours_ms = 6 * 60 * 60 * 1_000

      assert ms <= six_hours_ms
      assert ms >= six_hours_ms - 5_000
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
