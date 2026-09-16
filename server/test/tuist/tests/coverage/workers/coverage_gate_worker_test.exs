defmodule Tuist.Tests.Coverage.Workers.CoverageGateWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.GitHistory
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Workers.CoverageGateWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    project =
      ProjectsFixtures.project_fixture(
        account_id: account.id,
        default_branch: "main",
        vcs_connection: [repository_full_handle: "tuist/tuist", provider: :github]
      )

    {:ok, project} =
      Projects.update_project(project, %{
        coverage_gates_enabled: true,
        coverage_gate_min_patch_coverage: 50.0,
        coverage_gate_max_total_drop: 20.0
      })

    stub(Environment, :github_app_configured?, fn -> true end)
    stub(Environment, :app_url, fn opts -> "https://tuist.dev#{Keyword.get(opts, :path, "")}" end)

    GitHistory.record_commits(project.id, "sha1", [
      %{sha: "b", parents: [], committed_at: ~U[2026-09-01 00:00:00Z]},
      %{sha: "p", parents: ["b"], committed_at: ~U[2026-09-01 01:00:00Z]}
    ])

    CoverageFixtures.run_with_coverage(
      project,
      account,
      [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 1]), CoverageFixtures.file("Sources/B.swift", [1, 1])],
      %{git_commit_sha: "b", ran_at: ~N[2026-09-01 00:30:00]}
    )

    %{account: account, project: project}
  end

  defp pr_run(project, account, files, attrs \\ %{}) do
    CoverageFixtures.run_with_coverage(
      project,
      account,
      files,
      Map.merge(
        %{
          git_branch: "feature",
          git_commit_sha: "p",
          git_ref: "refs/pull/9/merge",
          base_branch: "main",
          merge_base_sha: "b",
          is_pull_request: true,
          pull_request_number: 9,
          history_source: "client",
          changed_files: [
            %{
              path: "Sources/A.swift",
              status: "modified",
              git_blob_id: "blob-Sources/A.swift",
              hunks: [%{start: 3, end: 4}]
            }
          ]
        },
        attrs
      )
    )
  end

  defp perform(project, run) do
    CoverageGateWorker.perform(%Oban.Job{args: %{"project_id" => project.id, "test_run_id" => run.id}})
  end

  test "posts a passing check run on the pull request's head commit", %{project: project, account: account} do
    run =
      pr_run(project, account, [
        CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 0]),
        CoverageFixtures.file("Sources/B.swift", [1, 1])
      ])

    expect(Client, :get_pull_request, fn %{pr_number: 9, repository_full_handle: "tuist/tuist"} ->
      {:ok, %{"head" => %{"sha" => "head-sha"}}}
    end)

    expect(Client, :create_check_run, fn params ->
      assert params.name == "tuist/coverage"
      assert params.head_sha == "head-sha"
      assert params.conclusion == "success"
      assert params.external_id == run.id
      assert params.details_url =~ "/tests/test-runs/#{run.id}?tab=coverage"
      assert params.output.title == "Coverage gates passed"
      assert params.output.summary =~ "| 83.3% (-16.7 pp against 100.0% at `b`) | 50.0% (1 of 2 changed lines) | none |"
      assert params.output.summary =~ "| Minimum patch coverage | 50.0% | 50.0% | ✅ |"
      assert params.output.summary =~ "| Maximum total drop | 20.0 pp | -16.7 pp | ✅ |"
      {:ok, %{"id" => 1}}
    end)

    assert :ok == perform(project, run)
  end

  test "fails the check when a gate is broken", %{project: project, account: account} do
    run =
      pr_run(project, account, [
        CoverageFixtures.file("Sources/A.swift", [1, 1, 0, 0]),
        CoverageFixtures.file("Sources/B.swift", [1, 1])
      ])

    stub(Client, :get_pull_request, fn _ -> {:error, :not_found} end)

    expect(Client, :create_check_run, fn params ->
      assert params.head_sha == "p"
      assert params.conclusion == "failure"
      assert params.output.summary =~ "| Minimum patch coverage | 50.0% | 0.0% | ❌ |"
      assert params.output.summary =~ "| Maximum total drop | 20.0 pp | -33.3 pp | ❌ |"
      assert params.output.summary =~ "| `Sources/A.swift` |"
      {:ok, %{"id" => 1}}
    end)

    assert :ok == perform(project, run)
  end

  test "is neutral when there is no baseline and the patch is unavailable", %{project: project, account: account} do
    run =
      pr_run(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 1])], %{
        merge_base_sha: "unknown",
        partial: true
      })

    stub(Client, :get_pull_request, fn _ -> {:error, :not_found} end)

    expect(Client, :create_check_run, fn params ->
      assert params.conclusion == "neutral"
      assert params.output.title == "Coverage gates could not be evaluated"
      assert params.output.summary =~ "100.0% (partial run, not compared)"
      assert params.output.summary =~ "unavailable: the run skipped tests"
      assert params.output.summary =~ "⚪ the run skipped tests"
      {:ok, %{"id" => 1}}
    end)

    assert :ok == perform(project, run)
  end

  test "posts nothing when the gates are off", %{project: project, account: account} do
    {:ok, project} = Projects.update_project(project, %{coverage_gates_enabled: false})
    run = pr_run(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 1])])

    reject(&Client.create_check_run/1)
    assert :ok == perform(project, run)
  end

  test "waits for a run that is not stored yet", %{project: project} do
    assert {:snooze, 30} == perform(project, %{id: UUIDv7.generate()})
  end
end
