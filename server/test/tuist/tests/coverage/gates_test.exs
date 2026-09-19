defmodule Tuist.Tests.Coverage.GatesTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Gates
  alias Tuist.Tests.Coverage.Workers.CoverageGateWorker
  alias Tuist.VCS.Workers.CommentWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")
    %{account: account, project: project}
  end

  defp gated(project, attrs) do
    {:ok, project} = Projects.update_project(project, Map.merge(%{coverage_gates_enabled: true}, attrs))
    project
  end

  defp comparison(attrs) do
    Map.merge(
      %{
        commit: %{sha: "p", partial: false, coverage: 70.0, schemes: ["App"], partial_schemes: []},
        baseline: %{coverage: 72.0, commit: "b"},
        baseline_reason: nil,
        total_delta: -2.0,
        schemes: [],
        patch: %{status: :available, covered_lines: 8, executable_lines: 10, coverage: 80.0},
        gaps: []
      },
      attrs
    )
  end

  describe "evaluate/2" do
    test "is neutral without any gate", %{project: project} do
      assert Gates.evaluate(gated(project, %{}), comparison(%{})) == %{conclusion: :neutral, checks: []}
    end

    test "passes when every gate holds", %{project: project} do
      project = gated(project, %{coverage_gate_min_patch_coverage: 80.0, coverage_gate_max_total_drop: 2.0})

      assert %{conclusion: :success, checks: [patch, drop]} = Gates.evaluate(project, comparison(%{}))
      assert {patch.gate, patch.value, patch.status} == {:min_patch_coverage, 80.0, :passed}
      assert {drop.gate, drop.value, drop.status} == {:max_total_drop, -2.0, :passed}
    end

    test "fails when a gate is broken", %{project: project} do
      project = gated(project, %{coverage_gate_min_patch_coverage: 90.0, coverage_gate_max_total_drop: 1.0})

      assert %{conclusion: :failure, checks: [%{status: :failed}, %{status: :failed}]} =
               Gates.evaluate(project, comparison(%{}))
    end

    test "passes the patch gate when the change has no executable lines", %{project: project} do
      project = gated(project, %{coverage_gate_min_patch_coverage: 90.0})

      assert %{conclusion: :success} =
               Gates.evaluate(
                 project,
                 comparison(%{patch: %{status: :available, covered_lines: 0, executable_lines: 0, coverage: 0.0}})
               )
    end

    test "is neutral, with the reason, when a gate cannot be evaluated", %{project: project} do
      project = gated(project, %{coverage_gate_min_patch_coverage: 50.0, coverage_gate_max_total_drop: 5.0})

      no_baseline =
        comparison(%{
          baseline: nil,
          baseline_reason: %{kind: :no_measured_commits, base_branch: "main", window_days: 90},
          total_delta: nil,
          patch: %{status: :unavailable, reason: :no_history}
        })

      assert %{conclusion: :neutral, checks: [patch, drop]} = Gates.evaluate(project, no_baseline)
      assert {patch.status, patch.reason} == {:neutral, %{status: :unavailable, reason: :no_history}}
      assert {drop.status, drop.reason.kind} == {:neutral, :no_measured_commits}

      partial =
        comparison(%{
          commit: %{sha: "p", partial: true, coverage: 70.0, schemes: ["App"], partial_schemes: ["App"]},
          total_delta: nil
        })

      assert %{conclusion: :neutral, checks: [%{status: :passed}, %{status: :neutral, reason: %{kind: :partial_run}}]} =
               Gates.evaluate(project, partial)
    end

    test "fails rather than staying neutral when one gate fails and another cannot be evaluated", %{project: project} do
      project = gated(project, %{coverage_gate_min_patch_coverage: 90.0, coverage_gate_max_total_drop: 5.0})

      assert %{conclusion: :failure} =
               Gates.evaluate(
                 project,
                 comparison(%{total_delta: nil, baseline: nil, baseline_reason: %{kind: :no_measured_commits}})
               )
    end
  end

  describe "the follow-up of a published coverage" do
    test "posts the commit's pending check and refreshes the comment of a pull request run", %{
      project: project,
      account: account
    } do
      project = gated(project, %{coverage_gate_min_patch_coverage: 50.0})

      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1])], %{
        is_pull_request: true,
        pull_request_number: 3,
        git_ref: "refs/pull/3/merge",
        git_branch: "feature"
      })

      assert_enqueued(
        worker: CoverageGateWorker,
        args: %{project_id: project.id, git_commit_sha: "abc123", git_ref: "refs/pull/3/merge", trigger: "run"}
      )

      assert_enqueued(worker: CommentWorker, args: %{project_id: project.id, git_ref: "refs/pull/3/merge"})
    end

    test "refreshes the comment but checks no gate for a project without gates", %{project: project, account: account} do
      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1])], %{
        is_pull_request: true,
        pull_request_number: 3,
        git_ref: "refs/pull/3/merge"
      })

      refute_enqueued(worker: CoverageGateWorker)
      assert_enqueued(worker: CommentWorker, args: %{git_ref: "refs/pull/3/merge"})
    end

    test "does nothing for a run on a branch, without a commit, or from a dirty checkout", %{
      project: project,
      account: account
    } do
      project = gated(project, %{})
      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1])], %{})

      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1])], %{
        is_pull_request: true,
        git_commit_sha: ""
      })

      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1])], %{
        is_pull_request: true,
        git_dirty: true
      })

      refute_enqueued(worker: CoverageGateWorker)
      refute_enqueued(worker: CommentWorker)
    end

    test "waits for the last shard of a sharded run", %{project: project, account: account} do
      project = gated(project, %{})
      plan = TuistTestSupport.Fixtures.ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)

      CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", [1])], %{
        is_pull_request: true,
        pull_request_number: 3,
        shard_plan_id: plan.id,
        shard_index: 0
      })

      refute_enqueued(worker: CoverageGateWorker)

      Tuist.Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        scheme: "App",
        git_branch: "main",
        git_commit_sha: "abc123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [],
        shard_plan_id: plan.id,
        shard_index: 1,
        xcode_coverage: %{partial: false, files: [CoverageFixtures.file("Sources/B.swift", [1])]}
      })

      assert_enqueued(worker: CoverageGateWorker, args: %{git_commit_sha: "abc123", trigger: "run"})
    end
  end
end
