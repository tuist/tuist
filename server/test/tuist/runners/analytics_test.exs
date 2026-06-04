defmodule Tuist.Runners.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.Analytics
  alias Tuist.Runners.Jobs

  # Walks a workflow_job through the full lifecycle so it lands as
  # `status=completed` with the supplied conclusion. Each step is a
  # separate INSERT, exactly like production — so without the GROUP
  # BY + argMax dedup in Analytics, the row would be counted three
  # times instead of once.
  defp completed_job(account, workflow_job_id, conclusion, opts \\ []) do
    fleet = Keyword.get(opts, :fleet, "fleet-analytics-#{workflow_job_id}")

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: fleet,
        repository: Keyword.get(opts, :repository, "acme/cli"),
        workflow_run_id: Keyword.get(opts, :workflow_run_id, workflow_job_id * 10),
        workflow_name: Keyword.get(opts, :workflow_name, ""),
        run_attempt: 1,
        job_name: Keyword.get(opts, :job_name, "build"),
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, candidate} = Jobs.pick_queued(fleet, [])
    :ok = Jobs.record_claimed(candidate, "pod-#{workflow_job_id}", DateTime.utc_now())
    :ok = Jobs.record_running(workflow_job_id, "runner-#{workflow_job_id}")
    Process.sleep(Keyword.get(opts, :run_ms, 20))
    {:ok, _} = Jobs.complete(workflow_job_id, conclusion)
  end

  describe "jobs_count/2" do
    test "counts one entry per workflow_job even after multiple state-transition inserts" do
      account = account_fixture()

      # Four lifecycle inserts each. Without dedup the analytics
      # subquery would over-count by 4× — this assertion catches a
      # regression to `count(workflow_job_id)` over raw rows.
      completed_job(account, 70_001, "success")
      completed_job(account, 70_002, "failure")

      assert %{count: 2} = Analytics.jobs_count(account.id)
    end

    test "scopes to the requested account" do
      mine = account_fixture()
      other = account_fixture()

      completed_job(mine, 71_001, "success")
      completed_job(other, 71_002, "success")

      assert %{count: 1} = Analytics.jobs_count(mine.id)
    end
  end

  describe "failed_jobs_count/2" do
    test "only counts workflow_jobs whose latest state is completed/failure" do
      account = account_fixture()

      completed_job(account, 72_001, "success")
      completed_job(account, 72_002, "failure")
      completed_job(account, 72_003, "cancelled")
      completed_job(account, 72_004, "skipped")

      # The dedup pattern picks the latest state per workflow_job,
      # so the count is 1 (the one with conclusion=failure) — even
      # though intermediate state rows (queued/claimed/running)
      # exist for every job.
      assert %{count: 1} = Analytics.failed_jobs_count(account.id)
    end
  end

  describe "bucket_for_window/2" do
    test "picks :hour for windows ≤ 36 hours" do
      now = DateTime.utc_now()
      start_dt = DateTime.add(now, -24, :hour)

      assert Analytics.bucket_for_window(start_dt, now) == :hour
    end

    test "picks :day for windows wider than 36 hours" do
      now = DateTime.utc_now()
      start_dt = DateTime.add(now, -7, :day)

      assert Analytics.bucket_for_window(start_dt, now) == :day
    end
  end

  describe "hourly bucketing" do
    test "jobs_count returns DateTime-keyed dates and hour-resolution buckets" do
      account = account_fixture()
      completed_job(account, 79_001, "success")

      now = DateTime.utc_now()
      result = Analytics.jobs_count(account.id, start_datetime: DateTime.add(now, -2, :hour), end_datetime: now)

      assert result.count == 1
      # Hourly mode → dates carry DateTime values (3 hour buckets:
      # floor(now-2h), floor(now-1h), floor(now)). The completion
      # lands in one of them; the others are zero-filled.
      assert Enum.all?(result.dates, &match?(%DateTime{}, &1))
      assert Enum.sum(result.values) == 1
    end
  end

  describe "successful_jobs_count/2" do
    test "only counts workflow_jobs whose latest state is completed/success" do
      account = account_fixture()

      completed_job(account, 72_101, "success")
      completed_job(account, 72_102, "success")
      completed_job(account, 72_103, "failure")
      completed_job(account, 72_104, "cancelled")
      completed_job(account, 72_105, "skipped")

      # Mirror of the failed_jobs_count assertion: dedup picks the
      # latest conclusion per workflow_job, so only the two with
      # conclusion=success are counted.
      assert %{count: 2} = Analytics.successful_jobs_count(account.id)
    end
  end

  describe "jobs_duration/2" do
    test "averages over deduplicated jobs (no double-counting per lifecycle row)" do
      account = account_fixture()

      completed_job(account, 73_001, "success", run_ms: 30)
      completed_job(account, 73_002, "success", run_ms: 30)

      result = Analytics.jobs_duration(account.id)

      # Two jobs, each ~30ms of runtime — the avg should be in the
      # tens of milliseconds, NOT three or four times that (which
      # would indicate row-level rather than workflow_job-level
      # aggregation).
      assert result.avg > 0
      assert result.avg < 10_000
    end
  end

  describe "workflows_duration/2" do
    test "excludes workflow_runs that still have non-completed jobs" do
      account = account_fixture()
      run_id = 9_500

      # Two jobs share a workflow_run. The first completes quickly;
      # the second stays queued. The run isn't done — its duration
      # shouldn't enter the rollup until every job has landed.
      # Without the all-completed HAVING gate, the rollup would
      # compute (first_completed - first_started) and report that
      # as the run's wall-clock, underreporting reality.
      completed_job(account, 78_001, "success", workflow_run_id: run_id, run_ms: 20)

      :ok =
        Jobs.enqueue(%{
          workflow_job_id: 78_002,
          account_id: account.id,
          fleet_name: "fleet-incomplete",
          repository: "acme/cli",
          workflow_run_id: run_id,
          workflow_name: "",
          run_attempt: 1,
          job_name: "still-queued",
          head_branch: "main",
          head_sha: "abc"
        })

      result = Analytics.workflows_duration(account.id)

      assert result.avg == 0
      assert result.p50 == 0
    end

    test "includes a workflow_run once every job is completed" do
      account = account_fixture()
      run_id = 9_600

      completed_job(account, 78_101, "success", workflow_run_id: run_id, run_ms: 20)
      completed_job(account, 78_102, "success", workflow_run_id: run_id, run_ms: 20)

      result = Analytics.workflows_duration(account.id)

      assert result.avg > 0
    end
  end

  describe "workflow_runs_count/2" do
    test "counts distinct workflow_run_ids" do
      account = account_fixture()

      # Two jobs sharing the same workflow_run_id collapse to one
      # workflow_run.
      completed_job(account, 74_001, "success", workflow_run_id: 9_000)
      completed_job(account, 74_002, "success", workflow_run_id: 9_000)
      completed_job(account, 74_003, "success", workflow_run_id: 9_001)

      assert %{count: 2} = Analytics.workflow_runs_count(account.id)
    end
  end

  describe "scope filters" do
    test "jobs_count respects :repository scope" do
      account = account_fixture()

      completed_job(account, 75_001, "success", repository: "acme/server")
      completed_job(account, 75_002, "success", repository: "acme/cli")

      assert %{count: 1} = Analytics.jobs_count(account.id, repository: "acme/server")
    end

    test "jobs_count respects :workflow_name scope" do
      account = account_fixture()

      completed_job(account, 76_001, "success", workflow_name: "Server")
      completed_job(account, 76_002, "success", workflow_name: "CLI")

      assert %{count: 1} = Analytics.jobs_count(account.id, workflow_name: "CLI")
    end

    test "jobs_count respects :platform scope via fleet_name prefix" do
      account = account_fixture()

      completed_job(account, 77_001, "success", fleet: "macos-large")
      completed_job(account, 77_002, "success", fleet: "linux-amd64")

      assert %{count: 1} = Analytics.jobs_count(account.id, platform: "macos")
      assert %{count: 1} = Analytics.jobs_count(account.id, platform: "linux")
    end

    test "jobs_count counts shape-catalog Linux pools under platform=linux" do
      # Profile-dispatched + legacy-alias jobs store `fleet_name` from
      # `Catalog.pool_name/2`, which doesn't start with `linux-` —
      # `tuist-runner-pool-linux-4vcpu-16gb` would silently fall into
      # "Other" if the filter only matched the legacy prefix. Both
      # naming conventions must surface under Linux.
      account = account_fixture()

      completed_job(account, 78_001, "success", fleet: "linux-amd64")
      completed_job(account, 78_002, "success", fleet: Tuist.Runners.Catalog.pool_name(4, 16))

      assert %{count: 2} = Analytics.jobs_count(account.id, platform: "linux")
      assert %{count: 0} = Analytics.jobs_count(account.id, platform: "macos")
    end
  end
end
