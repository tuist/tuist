defmodule Tuist.Tests.Coverage.Workers.CoverageGateWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Commits
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

    CoverageFixtures.seed_history(account, [CoverageFixtures.commit("b", [], 0), CoverageFixtures.commit("p", ["b"], 1)])

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

  defp perform(project, trigger, sha \\ "p") do
    CoverageGateWorker.perform(%Oban.Job{
      args: %{"project_id" => project.id, "git_commit_sha" => sha, "git_ref" => "refs/pull/9/merge", "trigger" => trigger}
    })
  end

  test "posts a pending check on the pull request's head until the commit signals completion", %{
    project: project,
    account: account
  } do
    pr_run(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 0])])

    expect(Client, :get_pull_request, fn %{pr_number: 9, repository_full_handle: "tuist/tuist"} ->
      {:ok, %{"head" => %{"sha" => "head-sha"}}}
    end)

    expect(Client, :create_check_run, fn params ->
      assert params.name == "tuist/coverage"
      assert params.head_sha == "head-sha"
      assert params.status == "in_progress"
      refute Map.has_key?(params, :conclusion) and params.conclusion
      assert params.external_id == "p"
      assert params.details_url == "https://tuist.dev/#{project.account.name}/#{project.name}/tests/coverage/commits/p"
      assert params.output.title == "Waiting for the coverage pipeline to finish"
      assert params.output.summary =~ "Coverage so far: 75.0% over `App`"
      {:ok, %{"id" => 1}}
    end)

    assert :ok == perform(project, "run")
  end

  test "posts the verdict on the signal, and leaves it alone when more runs land", %{
    project: project,
    account: account
  } do
    pr_run(project, account, [
      CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 0]),
      CoverageFixtures.file("Sources/B.swift", [1, 1])
    ])

    stub(Client, :get_pull_request, fn _ -> {:error, :not_found} end)
    Commits.recompute(project, "p", complete: true, completeness: "signal")

    expect(Client, :create_check_run, fn params ->
      assert params.head_sha == "p"
      assert params.status == "completed"
      assert params.conclusion == "success"
      assert params.output.title == "Coverage gates passed"
      assert params.output.summary =~ "| 83.3% (-16.7% against 100.0% at `b`) | 50.0% (1 of 2 changed lines) | none |"
      assert params.output.summary =~ "| Minimum patch coverage | 50.0% | 50.0% | ✅ |"
      assert params.output.summary =~ "| Maximum total drop | 20.0% | -16.7% | ✅ |"
      assert params.output.summary =~ "[View the commit's coverage](https://tuist.dev/"
      {:ok, %{"id" => 1}}
    end)

    assert :ok == perform(project, "signal")

    # A run reporting after the signal joins the commit but never reposts the check.
    reject(&Client.create_check_run/1)
    assert :ok == perform(project, "run")
  end

  test "fails the check when a gate is broken", %{project: project, account: account} do
    pr_run(project, account, [
      CoverageFixtures.file("Sources/A.swift", [1, 1, 0, 0]),
      CoverageFixtures.file("Sources/B.swift", [1, 1])
    ])

    stub(Client, :get_pull_request, fn _ -> {:error, :not_found} end)

    expect(Client, :create_check_run, fn params ->
      assert params.conclusion == "failure"
      assert params.output.summary =~ "| Minimum patch coverage | 50.0% | 0.0% | ❌ |"
      assert params.output.summary =~ "| Maximum total drop | 20.0% | -33.3% | ❌ |"
      assert params.output.summary =~ "| `Sources/A.swift` |"
      {:ok, %{"id" => 1}}
    end)

    assert :ok == perform(project, "signal")
  end

  test "is neutral when there is no baseline, the patch gate still holding on a partial run", %{project: project, account: account} do
    pr_run(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 1])], %{
      merge_base_sha: "unknown",
      partial: true
    })

    stub(Client, :get_pull_request, fn _ -> {:error, :not_found} end)

    expect(Client, :create_check_run, fn params ->
      assert params.conclusion == "neutral"
      assert params.output.title == "Coverage gates could not be evaluated"
      assert params.output.summary =~ "100.0% (no baseline: commit `unknown` is not in the repository's Git history)"
      assert params.output.summary =~ "| Minimum patch coverage | 50.0% | 100.0% | ✅ |"
      assert params.output.summary =~ "⚪ commit `unknown` is not in the repository's Git history"
      {:ok, %{"id" => 1}}
    end)

    assert :ok == perform(project, "signal")
  end

  test "posts nothing when the gates are off or the commit was never measured", %{project: project, account: account} do
    reject(&Client.create_check_run/1)
    assert :ok == perform(project, "signal", "unmeasured")

    {:ok, project} = Projects.update_project(project, %{coverage_gates_enabled: false})
    pr_run(project, account, [CoverageFixtures.file("Sources/A.swift", [1, 1, 1, 1])])
    assert :ok == perform(project, "signal")
  end
end
