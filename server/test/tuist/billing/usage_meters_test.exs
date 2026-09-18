defmodule Tuist.Billing.UsageMetersTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Billing.UsageMeters
  alias Tuist.Cache.CASEvent
  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent
  alias Tuist.Runners.Job
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  @period_start ~U[2026-05-01 00:00:00.000000Z]
  @period_end ~U[2026-05-02 00:00:00.000000Z]

  setup do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)

    %{account: account, project: project}
  end

  defp insert_kura_event(attrs) do
    IngestRepo.insert_all(UsageEvent, [
      Map.merge(
        %{
          event_id: "evt-#{System.unique_integer([:positive])}",
          project_id: 0,
          node_id: "kura-test",
          region: "eu-west",
          traffic_plane: "public",
          direction: "egress",
          operation: "download",
          protocol: "http",
          artifact_kind: "module",
          bytes: 0,
          request_count: 0,
          window_start: ~N[2026-05-01 12:00:00],
          window_seconds: 60,
          inserted_at: ~N[2026-05-01 12:01:00]
        },
        attrs
      )
    ])
  end

  defp insert_cas_event(attrs) do
    IngestRepo.insert_all(CASEvent, [
      Map.merge(
        %{
          id: UUIDv7.generate(),
          action: "download",
          size: 0,
          cas_id: "cas-#{System.unique_integer([:positive])}",
          cache_endpoint: "https://cache.tuist.dev",
          inserted_at: ~N[2026-05-01 12:00:00]
        },
        attrs
      )
    ])
  end

  defp insert_runner_job(account, workflow_run_id) do
    IngestRepo.insert_all(Job, [
      %{
        workflow_job_id: System.unique_integer([:positive]),
        account_id: account.id,
        fleet_name: "tuist-macos",
        repository: "acme/app",
        workflow_run_id: workflow_run_id,
        status: "completed",
        conclusion: "success",
        enqueued_at: ~U[2026-04-30 23:50:00.000000Z],
        updated_at: ~U[2026-05-01 00:30:00.000000Z]
      }
    ])
  end

  defp test_run(project, attrs \\ []) do
    {:ok, test_run} =
      RunsFixtures.test_fixture(
        Keyword.merge(
          [project_id: project.id, ran_at: ~N[2026-05-01 12:00:00.000000], test_modules: []],
          attrs
        )
      )

    test_run
  end

  defp test_case_runs(project, test_run, statuses, ran_at \\ ~N[2026-05-01 12:00:00.000000]) do
    Enum.each(statuses, fn status ->
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_run_id: test_run.id,
        status: status,
        ran_at: ran_at
      )
    end)
  end

  describe "cache_downloads/3" do
    test "reads Kura downloads by cache and marks traffic from runner cache regions", %{account: account} do
      insert_kura_event(%{account_id: account.id, artifact_kind: "module", bytes: 1_000, request_count: 2})
      insert_kura_event(%{account_id: account.id, artifact_kind: "reapi", bytes: 300, request_count: 3})
      insert_kura_event(%{account_id: account.id, artifact_kind: "nx", bytes: 40, request_count: 4})
      insert_kura_event(%{account_id: account.id, artifact_kind: "metro", bytes: 60, request_count: 6})

      insert_kura_event(%{
        account_id: account.id,
        artifact_kind: "xcode",
        region: "scw-fr-par-runners",
        bytes: 500,
        request_count: 5
      })

      assert account.id
             |> UsageMeters.cache_downloads(@period_start, @period_end)
             |> Enum.sort_by(& &1.cache) == [
               %{date: ~D[2026-05-01], cache: :bazel, runners: false, bytes: 300, requests: 3},
               %{date: ~D[2026-05-01], cache: :metro, runners: false, bytes: 60, requests: 6},
               %{date: ~D[2026-05-01], cache: :module, runners: false, bytes: 1_000, requests: 2},
               %{date: ~D[2026-05-01], cache: :nx, runners: false, bytes: 40, requests: 4},
               %{date: ~D[2026-05-01], cache: :xcode, runners: true, bytes: 500, requests: 5}
             ]
    end

    test "ignores uploads and counts a redelivered rollup once", %{account: account} do
      insert_kura_event(%{event_id: "evt-redelivered-#{account.id}", account_id: account.id, bytes: 1_000})

      insert_kura_event(%{
        event_id: "evt-redelivered-#{account.id}",
        account_id: account.id,
        bytes: 1_000,
        inserted_at: ~N[2026-05-01 12:05:00]
      })

      insert_kura_event(%{account_id: account.id, direction: "ingress", operation: "upload", bytes: 9_000})

      assert [%{bytes: 1_000}] = UsageMeters.cache_downloads(account.id, @period_start, @period_end)
    end

    test "counts a rollup starting on a period boundary only in the period it opens", %{account: account} do
      insert_kura_event(%{account_id: account.id, bytes: 1_000, window_start: ~N[2026-05-01 00:00:00]})
      insert_kura_event(%{account_id: account.id, bytes: 2_000, window_start: ~N[2026-05-02 00:00:00]})

      assert [%{bytes: 1_000}] = UsageMeters.cache_downloads(account.id, @period_start, @period_end)

      assert [%{bytes: 2_000}] =
               UsageMeters.cache_downloads(account.id, @period_end, ~U[2026-05-03 00:00:00.000000Z])
    end

    test "attributes compilation cache downloads to the account that owns the project", %{
      account: account,
      project: project
    } do
      other_project = ProjectsFixtures.project_fixture()

      insert_cas_event(%{project_id: project.id, size: 400})
      insert_cas_event(%{project_id: project.id, size: 600})
      insert_cas_event(%{project_id: project.id, action: "upload", size: 5_000})
      insert_cas_event(%{project_id: project.id, size: 7_000, inserted_at: ~N[2026-05-02 00:00:00]})
      insert_cas_event(%{project_id: other_project.id, size: 8_000})

      assert UsageMeters.cache_downloads(account.id, @period_start, @period_end) == [
               %{date: ~D[2026-05-01], cache: :xcode, runners: false, bytes: 1_000, requests: 2}
             ]
    end
  end

  describe "test_case_runs/3" do
    test "attributes test case runs to the account that owns the project, not the uploader", %{
      account: account,
      project: project
    } do
      uploader = AccountsFixtures.user_fixture(preload: [:account]).account
      test_run = test_run(project, account_id: uploader.id)
      test_case_runs(project, test_run, ["success", "success", "failure", "skipped"])

      assert account.id |> UsageMeters.test_case_runs(@period_start, @period_end) |> Enum.sort_by(& &1.status) == [
               %{date: ~D[2026-05-01], status: "failure", runners: false, count: 1},
               %{date: ~D[2026-05-01], status: "skipped", runners: false, count: 1},
               %{date: ~D[2026-05-01], status: "success", runners: false, count: 2}
             ]

      assert UsageMeters.test_case_runs(uploader.id, @period_start, @period_end) == []
    end

    test "separates test case runs whose test run came from a Tuist Runners job", %{
      account: account,
      project: project
    } do
      workflow_run_id = System.unique_integer([:positive])
      insert_runner_job(account, workflow_run_id)

      runner_run = test_run(project, ci_provider: "github", ci_run_id: Integer.to_string(workflow_run_id))
      test_case_runs(project, runner_run, ["success", "success", "failure"])

      other_ci_run = test_run(project, ci_provider: "github", ci_run_id: Integer.to_string(workflow_run_id + 1))
      test_case_runs(project, other_ci_run, ["success"])

      assert account.id
             |> UsageMeters.test_case_runs(@period_start, @period_end)
             |> Enum.sort_by(&{&1.runners, &1.status}) ==
               [
                 %{date: ~D[2026-05-01], status: "success", runners: false, count: 1},
                 %{date: ~D[2026-05-01], status: "failure", runners: true, count: 1},
                 %{date: ~D[2026-05-01], status: "success", runners: true, count: 2}
               ]
    end

    test "counts a test case run on a period boundary only in the period it opens", %{
      account: account,
      project: project
    } do
      test_run = test_run(project)
      test_case_runs(project, test_run, ["success"], ~N[2026-05-01 00:00:00.000000])
      test_case_runs(project, test_run, ["success", "success"], ~N[2026-05-02 00:00:00.000000])

      assert [%{count: 1}] = UsageMeters.test_case_runs(account.id, @period_start, @period_end)
      assert [%{count: 2}] = UsageMeters.test_case_runs(account.id, @period_end, ~U[2026-05-03 00:00:00.000000Z])
    end

    test "counts a re-inserted test case run once", %{account: account, project: project} do
      test_run = test_run(project)
      id = UUIDv7.generate()

      for {is_flaky, inserted_at} <- [{false, ~N[2026-05-01 12:00:00.000000]}, {true, ~N[2026-05-03 09:00:00.000000]}] do
        RunsFixtures.test_case_run_fixture(
          id: id,
          project_id: project.id,
          test_run_id: test_run.id,
          status: "success",
          is_flaky: is_flaky,
          ran_at: ~N[2026-05-01 12:00:00.000000],
          inserted_at: inserted_at
        )
      end

      assert [%{count: 1}] = UsageMeters.test_case_runs(account.id, @period_start, @period_end)
    end
  end
end
