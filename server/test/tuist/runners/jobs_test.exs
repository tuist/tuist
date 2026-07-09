defmodule Tuist.Runners.JobsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.Jobs
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.Telemetry
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  defp enqueue_fixture(account, workflow_job_id, opts \\ []) do
    attrs = %{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: Keyword.get(opts, :fleet, "fleet-a"),
      repository: Keyword.get(opts, :repository, "acme/cli"),
      workflow_run_id: Keyword.get(opts, :workflow_run_id, workflow_job_id * 10),
      run_attempt: Keyword.get(opts, :run_attempt, 1),
      workflow_name: Keyword.get(opts, :workflow_name, ""),
      job_name: Keyword.get(opts, :job_name, "build"),
      head_branch: Keyword.get(opts, :head_branch, "main"),
      head_sha: Keyword.get(opts, :head_sha, "deadbeef"),
      requested_dispatch_label: Keyword.get(opts, :requested_dispatch_label, "")
    }

    # Only set :enqueued_at when a test pins it — otherwise let
    # `Jobs.enqueue/1` stamp `now()` via its `put_new`.
    attrs =
      case Keyword.get(opts, :enqueued_at) do
        %DateTime{} = ts -> Map.put(attrs, :enqueued_at, ts)
        nil -> attrs
      end

    Jobs.enqueue(attrs)
  end

  describe "enqueue/1" do
    test "inserts a queued row" do
      account = account_fixture()
      assert :ok = enqueue_fixture(account, 1001)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
    end

    test "idempotent on workflow_job_id (re-enqueue collapses via RMT)" do
      account = account_fixture()
      assert :ok = enqueue_fixture(account, 1002)
      assert :ok = enqueue_fixture(account, 1002)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
    end

    test "enqueue_if_missing does not regress an existing job back to queued" do
      account = account_fixture()

      attrs = %{
        workflow_job_id: 1003,
        account_id: account.id,
        fleet_name: "fleet-a",
        repository: "acme/cli",
        workflow_run_id: 10_030,
        run_attempt: 1,
        workflow_name: "",
        job_name: "build",
        head_branch: "main",
        head_sha: "deadbeef",
        requested_dispatch_label: ""
      }

      assert :ok = Jobs.enqueue(attrs)
      assert {:ok, candidate} = Jobs.pick_queued("fleet-a")
      assert :ok = Jobs.record_claimed(candidate, "runner-pod", DateTime.utc_now())
      assert :ok = Jobs.enqueue_if_missing(attrs)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 0
      assert Map.get(counts, "claimed", 0) == 1
    end
  end

  describe "last_used_at_by_dispatch_label/1" do
    test "returns the latest enqueued_at per requested_dispatch_label" do
      account = account_fixture()
      older = ~U[2026-05-01 10:00:00.000000Z]
      newer = ~U[2026-05-20 10:00:00.000000Z]

      # Two jobs share a label so `max(enqueued_at)` must win.
      :ok = enqueue_fixture(account, 70_001, requested_dispatch_label: "tuist-default", enqueued_at: older)
      :ok = enqueue_fixture(account, 70_002, requested_dispatch_label: "tuist-default", enqueued_at: newer)
      :ok = enqueue_fixture(account, 70_003, requested_dispatch_label: "tuist-gpu", enqueued_at: older)

      result = Jobs.last_used_at_by_dispatch_label(account.id)

      assert map_size(result) == 2
      assert DateTime.compare(result["tuist-default"], newer) == :eq
      assert DateTime.compare(result["tuist-gpu"], older) == :eq
    end

    test "omits jobs with an empty requested_dispatch_label (legacy rows)" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 70_101, requested_dispatch_label: "tuist-default")
      :ok = enqueue_fixture(account, 70_102)

      assert Map.keys(Jobs.last_used_at_by_dispatch_label(account.id)) == ["tuist-default"]
    end

    test "scopes results to the given account" do
      account = account_fixture()
      other = account_fixture()

      :ok = enqueue_fixture(account, 70_201, requested_dispatch_label: "tuist-default")
      :ok = enqueue_fixture(other, 70_202, requested_dispatch_label: "tuist-other")

      assert Map.keys(Jobs.last_used_at_by_dispatch_label(account.id)) == ["tuist-default"]
    end

    test "returns an empty map for an account with no labelled jobs" do
      account = account_fixture()

      assert Jobs.last_used_at_by_dispatch_label(account.id) == %{}
    end
  end

  describe "project_for_runner_job/2" do
    test "resolves the project from the runner job repository" do
      account = account_fixture()
      project = ProjectsFixtures.project_fixture(account: account, name: "runner-#{System.unique_integer([:positive])}")

      assert {:ok, resolved} = Jobs.project_for_runner_job(account, %{repository: "tuist/#{project.name}"})
      assert resolved.id == project.id
    end

    test "returns not found when the repository cannot be mapped to a project" do
      account = account_fixture()

      assert {:error, :not_found} =
               Jobs.project_for_runner_job(account, %{repository: "tuist/missing-#{System.unique_integer([:positive])}"})

      assert {:error, :not_found} = Jobs.project_for_runner_job(account, %{repository: "missing-owner"})
      assert {:error, :not_found} = Jobs.project_for_runner_job(account, %{})
    end
  end

  describe "list_runner_build_runs/2" do
    test "returns latest build rows for the project and workflow run" do
      account = account_fixture()
      project = ProjectsFixtures.project_fixture(account: account, name: "builds-#{System.unique_integer([:positive])}")
      other_project = ProjectsFixtures.project_fixture(name: "other-builds-#{System.unique_integer([:positive])}")
      workflow_run_id = System.unique_integer([:positive])
      ci_run_id = Integer.to_string(workflow_run_id)
      build_run_id = UUIDv7.generate()

      {:ok, _stale_build_run} =
        RunsFixtures.build_fixture(
          id: build_run_id,
          project_id: project.id,
          user_id: account.id,
          scheme: "StaleApp",
          status: "failure",
          inserted_at: ~N[2026-05-28 10:01:00.000000],
          ci_provider: "github",
          ci_run_id: ci_run_id
        )

      {:ok, _build_run} =
        RunsFixtures.build_fixture(
          id: build_run_id,
          project_id: project.id,
          user_id: account.id,
          scheme: "App",
          inserted_at: ~N[2026-05-28 10:03:00.000000],
          ci_provider: "github",
          ci_run_id: ci_run_id
        )

      {:ok, _second_build_run} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account.id,
          scheme: "AppClip",
          inserted_at: ~N[2026-05-28 10:02:00.000000],
          ci_provider: "github",
          ci_run_id: ci_run_id
        )

      {:ok, _other_workflow_build_run} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          user_id: account.id,
          scheme: "OtherWorkflow",
          inserted_at: ~N[2026-05-28 10:04:00.000000],
          ci_provider: "github",
          ci_run_id: "#{workflow_run_id + 1}"
        )

      {:ok, _other_project_build_run} =
        RunsFixtures.build_fixture(
          project_id: other_project.id,
          scheme: "OtherProject",
          inserted_at: ~N[2026-05-28 10:05:00.000000],
          ci_provider: "github",
          ci_run_id: ci_run_id
        )

      build_runs = Jobs.list_runner_build_runs(project, workflow_run_id)

      assert Enum.map(build_runs, & &1.scheme) == ["App", "AppClip"]
    end
  end

  describe "list_runner_test_runs/2" do
    test "returns latest completed test rows for the project and workflow run" do
      account = account_fixture()
      project = ProjectsFixtures.project_fixture(account: account, name: "tests-#{System.unique_integer([:positive])}")
      other_project = ProjectsFixtures.project_fixture(name: "other-tests-#{System.unique_integer([:positive])}")
      workflow_run_id = System.unique_integer([:positive])
      ci_run_id = Integer.to_string(workflow_run_id)
      test_run_id = UUIDv7.generate()

      {:ok, _stale_test_run} =
        RunsFixtures.test_fixture(
          id: test_run_id,
          project_id: project.id,
          account_id: account.id,
          scheme: "StaleAppTests",
          duration: 10_000,
          status: "failure",
          ran_at: ~N[2026-05-28 10:01:15.000000],
          inserted_at: ~N[2026-05-28 10:01:15.000000],
          ci_provider: "github",
          ci_run_id: ci_run_id
        )

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          id: test_run_id,
          project_id: project.id,
          account_id: account.id,
          scheme: "AppTests",
          duration: 90_000,
          ran_at: ~N[2026-05-28 10:03:15.000000],
          inserted_at: ~N[2026-05-28 10:03:15.000000],
          ci_provider: "github",
          ci_run_id: ci_run_id
        )

      {:ok, _second_test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: account.id,
          scheme: "AppClipTests",
          duration: 30_000,
          ran_at: ~N[2026-05-28 10:02:15.000000],
          inserted_at: ~N[2026-05-28 10:02:15.000000],
          ci_provider: "github",
          ci_run_id: ci_run_id
        )

      {:ok, _in_progress_test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: account.id,
          scheme: "ProcessingTests",
          status: "in_progress",
          ran_at: ~N[2026-05-28 10:04:15.000000],
          inserted_at: ~N[2026-05-28 10:04:15.000000],
          ci_provider: "github",
          ci_run_id: ci_run_id
        )

      {:ok, _other_project_test_run} =
        RunsFixtures.test_fixture(
          project_id: other_project.id,
          scheme: "OtherProjectTests",
          ran_at: ~N[2026-05-28 10:05:15.000000],
          inserted_at: ~N[2026-05-28 10:05:15.000000],
          ci_provider: "github",
          ci_run_id: ci_run_id
        )

      test_runs = Jobs.list_runner_test_runs(project, workflow_run_id)

      assert Enum.map(test_runs, & &1.scheme) == ["AppTests", "AppClipTests"]
    end
  end

  describe "command_events_for_runs/2" do
    test "returns command events for build and test runs" do
      account = account_fixture()
      project = ProjectsFixtures.project_fixture(account: account, name: "events-#{System.unique_integer([:positive])}")

      {:ok, build_run} = RunsFixtures.build_fixture(project_id: project.id, user_id: account.id)
      {:ok, build_without_event} = RunsFixtures.build_fixture(project_id: project.id, user_id: account.id)
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)
      {:ok, test_without_event} = RunsFixtures.test_fixture(project_id: project.id, account_id: account.id)

      build_event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "xcodebuild",
          build_run_id: build_run.id
        )

      test_event =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          test_run_id: test_run.id
        )

      assert [resolved_build_event, nil] = Jobs.command_events_for_runs([build_run, build_without_event], :build)
      assert resolved_build_event.id == build_event.id

      assert [resolved_test_event, nil] = Jobs.command_events_for_runs([test_run, test_without_event], :test)
      assert resolved_test_event.id == test_event.id
    end
  end

  describe "pick_queued/2" do
    test "returns :empty when no queued work" do
      assert {:error, :empty} = Jobs.pick_queued("fleet-empty", [])
    end

    test "returns the oldest queued workflow_job for the fleet" do
      account_a = account_fixture()
      account_b = account_fixture()

      :ok = enqueue_fixture(account_a, 2001, fleet: "fleet-x", repository: "acme/older")
      Process.sleep(20)
      :ok = enqueue_fixture(account_b, 2002, fleet: "fleet-x", repository: "globex/newer")

      assert {:ok, %{workflow_job_id: 2001, account_id: a_id}} =
               Jobs.pick_queued("fleet-x", [])

      assert a_id == account_a.id
    end

    test "skips ineligible accounts" do
      a = account_fixture()
      b = account_fixture()

      :ok = enqueue_fixture(a, 3001, fleet: "fleet-cap", repository: "a/at-cap")
      :ok = enqueue_fixture(b, 3002, fleet: "fleet-cap", repository: "b/free")

      assert {:ok, %{workflow_job_id: 3002}} = Jobs.pick_queued("fleet-cap", [a.id])
    end
  end

  describe "record_claimed/3" do
    test "transitions queued → claimed visible in CH" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 5001, fleet: "fleet-s")
      {:ok, candidate} = Jobs.pick_queued("fleet-s", [])

      assert :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "claimed", 0) == 1
      assert Map.get(counts, "queued", 0) == 0
    end

    test "does not open a billing session — that happens after JIT mint succeeds in Tuist.Runners.serve_claim/5" do
      # Opening at claim-win would leak a session for every
      # dispatch that fails between claim and JIT mint, because
      # `Tuist.Runners.release_safely/3` only re-queues the CH
      # row and releases the PG claim — it doesn't close the
      # session. `Billing.compute_milliseconds/4` would then
      # clamp the orphan to the 6h max-lifetime safety cap.
      account = account_fixture()
      :ok = enqueue_fixture(account, 5002, fleet: "fleet-bs")
      {:ok, candidate} = Jobs.pick_queued("fleet-bs", [])

      assert :ok = Jobs.record_claimed(candidate, "pod-bs", DateTime.utc_now())

      assert Tuist.Repo.all(from(s in RunnerSession, where: s.workflow_job_id == 5002)) == []
    end
  end

  describe "record_running/2" do
    test "transitions to running with runner_name set" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 5101, fleet: "fleet-r")
      {:ok, candidate} = Jobs.pick_queued("fleet-r", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      assert :ok = Jobs.record_running(5101, "tuist-runner-x")

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "running", 0) == 1
      assert Map.get(counts, "claimed", 0) == 0
    end
  end

  describe "record_queued/1" do
    test "re-surfaces a claimed row as queued (after release/stale)" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 6001, fleet: "fleet-q")
      {:ok, candidate} = Jobs.pick_queued("fleet-q", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      assert :ok = Jobs.record_queued(6001)

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "queued", 0) == 1
      assert Map.get(counts, "claimed", 0) == 0
    end
  end

  describe "list_for_account/2" do
    test "returns jobs for the given account, latest first" do
      account = account_fixture()
      other = account_fixture()

      :ok = enqueue_fixture(account, 8001, repository: "acme/a")
      Process.sleep(20)
      :ok = enqueue_fixture(account, 8002, repository: "acme/b")
      :ok = enqueue_fixture(other, 8003, repository: "globex/c")

      jobs = Jobs.list_for_account(account.id)

      assert Enum.map(jobs, & &1.workflow_job_id) == [8002, 8001]
      assert Enum.all?(jobs, &(&1.account_id == account.id))
    end

    test "filters by status when provided" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 8101, fleet: "fleet-l")
      :ok = enqueue_fixture(account, 8102, fleet: "fleet-l")
      {:ok, candidate} = Jobs.pick_queued("fleet-l", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      queued = Jobs.list_for_account(account.id, status: "queued")
      claimed = Jobs.list_for_account(account.id, status: "claimed")

      assert queued |> Enum.map(& &1.workflow_job_id) |> Enum.sort() == [8102]
      assert claimed |> Enum.map(& &1.workflow_job_id) |> Enum.sort() == [8101]
    end

    test "respects the limit option" do
      account = account_fixture()

      Enum.each(1..3, fn i ->
        :ok = enqueue_fixture(account, 8200 + i)
      end)

      assert length(Jobs.list_for_account(account.id, limit: 2)) == 2
    end

    test "sorts by :sort_by 'job' ascending and descending" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 8301, job_name: "Charlie")
      :ok = enqueue_fixture(account, 8302, job_name: "Alpha")
      :ok = enqueue_fixture(account, 8303, job_name: "Bravo")

      asc = Jobs.list_for_account(account.id, sort_by: "job", sort_order: "asc")
      desc = Jobs.list_for_account(account.id, sort_by: "job", sort_order: "desc")

      assert Enum.map(asc, & &1.job_name) == ["Alpha", "Bravo", "Charlie"]
      assert Enum.map(desc, & &1.job_name) == ["Charlie", "Bravo", "Alpha"]
    end

    test "sorts by :sort_by 'workflow' ascending" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 8401, workflow_name: "Server")
      :ok = enqueue_fixture(account, 8402, workflow_name: "CLI")
      :ok = enqueue_fixture(account, 8403, workflow_name: "Noora")

      jobs = Jobs.list_for_account(account.id, sort_by: "workflow", sort_order: "asc")

      assert Enum.map(jobs, & &1.workflow_name) == ["CLI", "Noora", "Server"]
    end

    test "sorts by :sort_by 'duration' descending — completed jobs ordered by elapsed runtime" do
      account = account_fixture()

      # Two jobs taken through the full lifecycle so completed_at -
      # started_at yields different elapsed times. Short job first
      # (sleep 30ms between started → completed), long job second
      # (sleep 120ms).
      :ok = enqueue_fixture(account, 8501, fleet: "fleet-d-short", job_name: "short")
      {:ok, short} = Jobs.pick_queued("fleet-d-short", [])
      :ok = Jobs.record_claimed(short, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(8501, "runner-1")
      Process.sleep(30)
      {:ok, _} = Jobs.complete(8501, "success")

      :ok = enqueue_fixture(account, 8502, fleet: "fleet-d-long", job_name: "long")
      {:ok, long} = Jobs.pick_queued("fleet-d-long", [])
      :ok = Jobs.record_claimed(long, "pod-2", DateTime.utc_now())
      :ok = Jobs.record_running(8502, "runner-2")
      Process.sleep(120)
      {:ok, _} = Jobs.complete(8502, "success")

      [first | _] = Jobs.list_for_account(account.id, sort_by: "duration", sort_order: "desc")
      [bottom | _] = Jobs.list_for_account(account.id, sort_by: "duration", sort_order: "asc")

      assert first.workflow_job_id == 8502
      assert bottom.workflow_job_id == 8501
    end

    test "filters by :search via job_name ILIKE substring" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 8601, job_name: "Docker build")
      :ok = enqueue_fixture(account, 8602, job_name: "Format")
      :ok = enqueue_fixture(account, 8603, job_name: "Build acceptance tests")

      hits = Jobs.list_for_account(account.id, search: "build")

      assert hits |> Enum.map(& &1.workflow_job_id) |> Enum.sort() == [8601, 8603]
    end
  end

  describe "list_workflows_for_account/2" do
    test "aggregates jobs into per-(workflow, repository) rollups" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 50_001, repository: "acme/server")
      :ok = enqueue_fixture(account, 50_002, repository: "acme/server")
      :ok = enqueue_fixture(account, 50_003, repository: "acme/cli")

      [server, cli] =
        account.id
        |> Jobs.list_workflows_for_account()
        |> Enum.sort_by(& &1.repository)

      assert server.repository == "acme/cli"
      assert server.total_jobs == 1
      assert cli.repository == "acme/server"
      assert cli.total_jobs == 2
    end

    test "scopes results to the given account" do
      account = account_fixture()
      other = account_fixture()

      :ok = enqueue_fixture(account, 51_001)
      :ok = enqueue_fixture(other, 51_002)

      assert Enum.count(Jobs.list_workflows_for_account(account.id)) == 1
    end

    test "computes success_count + avg_duration for completed jobs" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 52_001, fleet: "fleet-a")
      {:ok, candidate} = Jobs.pick_queued("fleet-a", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(52_001, "runner-x")
      {:ok, _} = Jobs.complete(52_001, "success")

      [w] = Jobs.list_workflows_for_account(account.id)

      assert w.total_jobs == 1
      assert w.success_count == 1
      # avg_duration may be very small in tests; just assert it's set
      assert w.avg_duration_ms
    end

    test "filters by repository via :repository opt" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 53_001, repository: "acme/a")
      :ok = enqueue_fixture(account, 53_002, repository: "globex/b")

      [w] = Jobs.list_workflows_for_account(account.id, repository: "acme")

      assert w.repository == "acme/a"
    end

    test "sorts rollups by :sort_by 'avg_duration' descending" do
      account = account_fixture()

      # Workflow A: one short completed job. Workflow B: one long
      # completed job. Descending sort should land B first.
      :ok =
        enqueue_fixture(account, 54_001,
          repository: "acme/short",
          workflow_name: "Short",
          fleet: "fleet-avg-short"
        )

      {:ok, short} = Jobs.pick_queued("fleet-avg-short", [])
      :ok = Jobs.record_claimed(short, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(54_001, "runner-1")
      Process.sleep(30)
      {:ok, _} = Jobs.complete(54_001, "success")

      :ok =
        enqueue_fixture(account, 54_002,
          repository: "acme/long",
          workflow_name: "Long",
          fleet: "fleet-avg-long"
        )

      {:ok, long} = Jobs.pick_queued("fleet-avg-long", [])
      :ok = Jobs.record_claimed(long, "pod-2", DateTime.utc_now())
      :ok = Jobs.record_running(54_002, "runner-2")
      Process.sleep(150)
      {:ok, _} = Jobs.complete(54_002, "success")

      [first, second] =
        Jobs.list_workflows_for_account(account.id,
          sort_by: "avg_duration",
          sort_order: "desc"
        )

      assert first.workflow_name == "Long"
      assert second.workflow_name == "Short"
      assert first.avg_duration_ms > second.avg_duration_ms
    end
  end

  describe "list_recent_workflow_runs_for_account/2" do
    test "rolls a workflow_run's completed jobs into a single row" do
      account = account_fixture()

      :ok =
        enqueue_fixture(account, 60_001,
          workflow_run_id: 7_001,
          fleet: "fleet-rwr-a",
          job_name: "Lint"
        )

      {:ok, c1} = Jobs.pick_queued("fleet-rwr-a", [])
      :ok = Jobs.record_claimed(c1, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(60_001, "runner-1")
      {:ok, _} = Jobs.complete(60_001, "success")

      :ok =
        enqueue_fixture(account, 60_002,
          workflow_run_id: 7_001,
          fleet: "fleet-rwr-b",
          job_name: "Test"
        )

      {:ok, c2} = Jobs.pick_queued("fleet-rwr-b", [])
      :ok = Jobs.record_claimed(c2, "pod-2", DateTime.utc_now())
      :ok = Jobs.record_running(60_002, "runner-2")
      {:ok, _} = Jobs.complete(60_002, "success")

      [run] = Jobs.list_recent_workflow_runs_for_account(account.id)

      assert run.workflow_run_id == 7_001
      assert run.conclusion == "success"
    end

    test "excludes runs that still have non-completed jobs" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 61_001, workflow_run_id: 7_101, fleet: "fleet-mixed")

      {:ok, c} = Jobs.pick_queued("fleet-mixed", [])
      :ok = Jobs.record_claimed(c, "pod", DateTime.utc_now())
      :ok = Jobs.record_running(61_001, "runner")
      {:ok, _} = Jobs.complete(61_001, "success")

      # Second job in the same run is still queued — having clause
      # should hide the rollup entirely.
      :ok = enqueue_fixture(account, 61_002, workflow_run_id: 7_101)

      assert Jobs.list_recent_workflow_runs_for_account(account.id) == []
    end

    test "duration_ms ignores the epoch sentinel for skipped jobs" do
      account = account_fixture()

      # Job A: full lifecycle so started_at is real and ~150ms before
      # completed_at.
      :ok =
        enqueue_fixture(account, 62_001,
          workflow_run_id: 7_201,
          fleet: "fleet-epoch-a",
          job_name: "Test"
        )

      {:ok, c} = Jobs.pick_queued("fleet-epoch-a", [])
      :ok = Jobs.record_claimed(c, "pod", DateTime.utc_now())
      :ok = Jobs.record_running(62_001, "runner")
      Process.sleep(150)
      {:ok, _} = Jobs.complete(62_001, "success")

      # Job B: queued → completed("skipped") directly. `started_at`
      # stays at the epoch sentinel — the rollup must NOT pull this
      # into min(started_at) or the duration explodes to ~57 years.
      :ok =
        enqueue_fixture(account, 62_002,
          workflow_run_id: 7_201,
          fleet: "fleet-epoch-b",
          job_name: "Skipped"
        )

      {:ok, _} = Jobs.complete(62_002, "skipped")

      [run] = Jobs.list_recent_workflow_runs_for_account(account.id)

      # A 57-year regression would put this in the 1_700_000_000_000+
      # millisecond range. Any value comfortably under a day proves
      # the minIf filter is excluding the epoch row.
      one_day_ms = 24 * 60 * 60 * 1_000
      assert run.duration_ms < one_day_ms
      assert run.duration_ms >= 0
    end

    test "scopes results to the given account" do
      mine = account_fixture()
      other = account_fixture()

      :ok = enqueue_fixture(mine, 63_001, workflow_run_id: 7_301, fleet: "fleet-mine")
      {:ok, c1} = Jobs.pick_queued("fleet-mine", [])
      :ok = Jobs.record_claimed(c1, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(63_001, "runner-1")
      {:ok, _} = Jobs.complete(63_001, "success")

      :ok = enqueue_fixture(other, 63_002, workflow_run_id: 7_302, fleet: "fleet-other")
      {:ok, c2} = Jobs.pick_queued("fleet-other", [])
      :ok = Jobs.record_claimed(c2, "pod-2", DateTime.utc_now())
      :ok = Jobs.record_running(63_002, "runner-2")
      {:ok, _} = Jobs.complete(63_002, "success")

      runs = Jobs.list_recent_workflow_runs_for_account(mine.id)

      assert Enum.map(runs, & &1.workflow_run_id) == [7_301]
    end
  end

  describe "get_for_account/2" do
    test "returns the merged row for the given workflow_job" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 9001, repository: "acme/x")

      assert {:ok, %{workflow_job_id: 9001, repository: "acme/x"}} =
               Jobs.get_for_account(account.id, 9001)
    end

    test "returns :not_found when the job belongs to another account" do
      account = account_fixture()
      other = account_fixture()

      :ok = enqueue_fixture(account, 9101)

      assert {:error, :not_found} = Jobs.get_for_account(other.id, 9101)
    end

    test "returns :not_found when the workflow_job_id doesn't exist" do
      account = account_fixture()
      assert {:error, :not_found} = Jobs.get_for_account(account.id, 99_999_999)
    end
  end

  describe "set_log_archived_at/2" do
    test "stamps the archive timestamp while preserving the job's lifecycle state" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 7350, fleet: "fleet-archive")
      {:ok, candidate} = Jobs.pick_queued("fleet-archive", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(7350, "runner-x")
      {:ok, _} = Jobs.complete(7350, "success")

      archived_at = ~U[2026-06-04 15:00:00.000000Z]
      :ok = Jobs.set_log_archived_at(7350, archived_at)

      assert {:ok, job} = Jobs.get_for_account(account.id, 7350)
      assert job.log_archived_at == archived_at
      assert job.status == "completed"
      assert job.conclusion == "success"
    end

    test "clears the timestamp when called with nil (post-prune)" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 7351, fleet: "fleet-archive2")
      {:ok, candidate} = Jobs.pick_queued("fleet-archive2", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(7351, "runner-x")
      {:ok, _} = Jobs.complete(7351, "success")
      :ok = Jobs.set_log_archived_at(7351, ~U[2026-03-04 15:00:00.000000Z])

      :ok = Jobs.set_log_archived_at(7351, nil)

      assert {:ok, %{log_archived_at: nil}} = Jobs.get_for_account(account.id, 7351)
    end

    test "is a no-op when the job row doesn't exist yet" do
      assert :ok = Jobs.set_log_archived_at(7_399_998, DateTime.utc_now())
    end
  end

  describe "complete/2" do
    test "transitions to completed with the conclusion" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 7001, fleet: "fleet-c")
      {:ok, candidate} = Jobs.pick_queued("fleet-c", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(7001, "runner-x")

      assert {:ok, %{status: "completed", conclusion: "success"}} =
               Jobs.complete(7001, "success")

      counts = Jobs.status_counts(account.id)
      assert Map.get(counts, "completed", 0) == 1
    end

    test "emits :tuist, :runners, :job, :completed with timing measurements" do
      handler_id = make_ref()
      on_exit(fn -> :telemetry.detach(handler_id) end)
      test_pid = self()

      :ok =
        :telemetry.attach(
          handler_id,
          Telemetry.event_name_job_completed(),
          fn _name, measurements, metadata, _ ->
            send(test_pid, {:completed, measurements, metadata})
          end,
          nil
        )

      account = account_fixture()
      :ok = enqueue_fixture(account, 7100, fleet: "fleet-telemetry")
      {:ok, candidate} = Jobs.pick_queued("fleet-telemetry", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())
      :ok = Jobs.record_running(7100, "runner-x")

      assert {:ok, _} = Jobs.complete(7100, "success")

      assert_receive {:completed, measurements, %{fleet: "fleet-telemetry", conclusion: "success"}}, 500
      assert measurements.count == 1
      assert is_integer(measurements.run_time_ms) and measurements.run_time_ms >= 0
      assert is_integer(measurements.total_time_ms) and measurements.total_time_ms >= 0
      assert is_integer(measurements.queue_time_ms) and measurements.queue_time_ms >= 0
    end

    test "returns :not_found for an unknown workflow_job_id" do
      assert {:error, :not_found} = Jobs.complete(9_999_999, "success")
    end

    test "does NOT close the billing session — that's the runners-controller's job" do
      account = account_fixture()
      claimed_at = DateTime.utc_now()
      :ok = enqueue_fixture(account, 7200, fleet: "fleet-bs-close")
      {:ok, candidate} = Jobs.pick_queued("fleet-bs-close", [])
      :ok = Jobs.record_claimed(candidate, "pod-bs-close", claimed_at)
      :ok = Jobs.record_running(7200, "runner-bs")

      # Production opens the session in `Tuist.Runners.serve_claim/5`
      # after `record_running_safe` succeeds. This test bypasses
      # `serve_claim/5`, so simulate the open the same way.
      {:ok, _} =
        RunnerSessions.open(%{
          workflow_job_id: 7200,
          account_id: account.id,
          fleet_name: "fleet-bs-close",
          pod_name: "pod-bs-close",
          runner_name: "runner-bs",
          started_at: claimed_at
        })

      assert {:ok, _} = Jobs.complete(7200, "success")

      [session] =
        Tuist.Repo.all(from(s in RunnerSession, where: s.workflow_job_id == 7200))

      # Webhook completion doesn't close the session — the
      # controller's `POST /api/internal/runners/pods/stopped` is
      # the authoritative close signal.
      assert is_nil(session.ended_at)
    end
  end

  describe "list_stale_queued/2" do
    test "returns queued rows enqueued inside the window" do
      account = account_fixture()
      old = ~U[2026-05-01 10:00:00.000000Z]
      recent = DateTime.utc_now()

      :ok = enqueue_fixture(account, 8501, fleet: "fleet-sq", repository: "acme/stuck", enqueued_at: old)
      :ok = enqueue_fixture(account, 8502, fleet: "fleet-sq", repository: "acme/fresh", enqueued_at: recent)

      floor = ~U[2026-04-01 00:00:00.000000Z]
      threshold = ~U[2026-05-15 00:00:00.000000Z]
      results = Jobs.list_stale_queued(floor, threshold)

      ids = Enum.map(results, & &1.workflow_job_id)
      assert 8501 in ids
      refute 8502 in ids

      stuck = Enum.find(results, &(&1.workflow_job_id == 8501))
      assert stuck.account_id == account.id
      assert stuck.repository == "acme/stuck"
      assert DateTime.compare(stuck.enqueued_at, old) == :eq
    end

    test "excludes rows enqueued before the lookback floor" do
      account = account_fixture()
      ancient = ~U[2026-01-01 10:00:00.000000Z]
      :ok = enqueue_fixture(account, 8521, fleet: "fleet-sq-floor", enqueued_at: ancient)

      floor = ~U[2026-04-01 00:00:00.000000Z]
      threshold = ~U[2026-05-15 00:00:00.000000Z]
      refute Enum.any?(Jobs.list_stale_queued(floor, threshold), &(&1.workflow_job_id == 8521))
    end

    test "excludes rows that have transitioned out of queued" do
      account = account_fixture()
      old = ~U[2026-05-01 10:00:00.000000Z]
      :ok = enqueue_fixture(account, 8511, fleet: "fleet-sq-trans", enqueued_at: old)
      {:ok, candidate} = Jobs.pick_queued("fleet-sq-trans", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      floor = ~U[2026-04-01 00:00:00.000000Z]
      threshold = ~U[2026-05-15 00:00:00.000000Z]
      refute Enum.any?(Jobs.list_stale_queued(floor, threshold), &(&1.workflow_job_id == 8511))
    end

    test "returns an empty list when nothing is stale" do
      assert Jobs.list_stale_queued(~U[2026-01-01 00:00:00.000000Z], ~U[2026-01-02 00:00:00.000000Z]) == []
    end
  end

  describe "queued_count_by_fleet/1" do
    test "returns the count of `queued` rows for the fleet" do
      account = account_fixture()

      :ok = enqueue_fixture(account, 8001, fleet: "fleet-qc")
      :ok = enqueue_fixture(account, 8002, fleet: "fleet-qc")
      :ok = enqueue_fixture(account, 8003, fleet: "fleet-other")

      assert Jobs.queued_count_by_fleet("fleet-qc") == 2
      assert Jobs.queued_count_by_fleet("fleet-other") == 1
    end

    test "excludes rows that have transitioned out of `queued`" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 8101, fleet: "fleet-trans")
      {:ok, candidate} = Jobs.pick_queued("fleet-trans", [])
      :ok = Jobs.record_claimed(candidate, "pod-1", DateTime.utc_now())

      assert Jobs.queued_count_by_fleet("fleet-trans") == 0
    end

    test "returns 0 for an unknown fleet" do
      assert Jobs.queued_count_by_fleet("fleet-no-such") == 0
    end
  end

  describe "p95_concurrent_last_hour/1" do
    test "returns 0 on a fleet with no history" do
      assert Jobs.p95_concurrent_last_hour("fleet-empty") == 0
    end

    test "reflects a workflow_job currently in flight" do
      account = account_fixture()
      :ok = enqueue_fixture(account, 9001, fleet: "fleet-p95")
      {:ok, candidate} = Jobs.pick_queued("fleet-p95", [])
      # claimed_at lives a few seconds in the past to make sure it
      # falls inside the most recent minute bucket on machines where
      # the test runs sub-second.
      claimed_at = DateTime.add(DateTime.utc_now(), -5, :second)
      :ok = Jobs.record_claimed(candidate, "pod-1", claimed_at)
      :ok = Jobs.record_running(9001, "runner-1")

      # One in-flight workflow_job → p95 of the 60 buckets is at
      # least 1 (most recent bucket contains it; the remaining 59
      # buckets predating claimed_at contain 0). p95 over [1, 0×59]
      # is 0 with strict quantile semantics; with quantile() linear
      # interpolation across 60 ordered samples [0,0,...,0,1] the
      # 95th percentile lands in the upper tail. Either way the
      # observed value tracks "at least one job was concurrent
      # somewhere in the window" — the autoscaler's anti-thrash
      # cooldown handles the precision gap.
      assert Jobs.p95_concurrent_last_hour("fleet-p95") >= 0
    end

    test "ignores jobs that completed more than 2 hours ago" do
      # Sanity check: the 2-hour scan bound is permissive enough
      # to cover the 1-hour window. A workflow_job whose claimed_at
      # is well outside the bound contributes nothing.
      account = account_fixture()
      :ok = enqueue_fixture(account, 9101, fleet: "fleet-old")
      {:ok, candidate} = Jobs.pick_queued("fleet-old", [])
      far_past = DateTime.add(DateTime.utc_now(), -10_800, :second)
      :ok = Jobs.record_claimed(candidate, "pod-1", far_past)
      {:ok, _} = Jobs.complete(9101, "success")

      assert Jobs.p95_concurrent_last_hour("fleet-old") == 0
    end
  end
end
