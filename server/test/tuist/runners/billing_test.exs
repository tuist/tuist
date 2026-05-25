defmodule Tuist.Runners.BillingTest do
  use TuistTestSupport.Cases.DataCase

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
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
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

  describe "compute_milliseconds_per_day/3" do
    test "buckets a single session into its UTC day" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      session_fixture(account,
        started_at: ~U[2026-05-10 12:00:00.000000Z],
        ended_at: ~U[2026-05-10 12:05:00.000000Z]
      )

      result = Billing.compute_milliseconds_per_day(account.id, period_start, period_end)

      assert Map.get(result, ~D[2026-05-10]) == 5 * 60 * 1_000
    end

    test "splits a midnight-spanning session across the two affected days" do
      account = account_fixture()
      period_start = ~U[2026-05-01 00:00:00.000000Z]
      period_end = ~U[2026-05-31 23:59:59.999999Z]

      # 23:50 May 10 → 00:10 May 11 = 20 minutes total. 10 mins
      # belong to May 10, 10 mins to May 11.
      session_fixture(account,
        started_at: ~U[2026-05-10 23:50:00.000000Z],
        ended_at: ~U[2026-05-11 00:10:00.000000Z]
      )

      result = Billing.compute_milliseconds_per_day(account.id, period_start, period_end)

      assert_in_delta Map.get(result, ~D[2026-05-10]), 10 * 60 * 1_000, 1_000
      assert_in_delta Map.get(result, ~D[2026-05-11]), 10 * 60 * 1_000, 1_000
    end
  end
end
