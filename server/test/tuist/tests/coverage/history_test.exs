defmodule Tuist.Tests.Coverage.HistoryTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Tests.Coverage.History
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")
    %{account: account, project: project}
  end

  defp run(project, account, attrs, counts) do
    CoverageFixtures.run_with_coverage(project, account, [CoverageFixtures.file("Sources/A.swift", counts)], attrs)
  end

  describe "branch_points/4 and latest/4" do
    test "give one point per commit from the newest full run of the scheme", %{project: project, account: account} do
      run(project, account, %{git_commit_sha: "a", ran_at: ~N[2026-09-01 10:00:00]}, [1, 0, 0, 0])
      run(project, account, %{git_commit_sha: "b", ran_at: ~N[2026-09-02 10:00:00]}, [1, 1, 0, 0])
      newest_b = run(project, account, %{git_commit_sha: "b", ran_at: ~N[2026-09-02 11:00:00]}, [1, 1, 1, 0])
      run(project, account, %{git_commit_sha: "c", ran_at: ~N[2026-09-03 10:00:00], partial: true}, [1, 1, 1, 1])
      run(project, account, %{git_commit_sha: "c", ran_at: ~N[2026-09-03 10:00:00], scheme: "Other"}, [1, 1, 1, 1])
      run(project, account, %{git_commit_sha: "d", ran_at: ~N[2026-09-04 10:00:00], git_branch: "feature"}, [0, 0, 0, 0])

      points = History.branch_points(project.id, "main", "App")

      assert Enum.map(points, &{&1.git_commit_sha, &1.coverage}) == [{"a", 25.0}, {"b", 75.0}]
      assert Enum.at(points, 1).test_run_id == newest_b.id

      assert %{git_commit_sha: "b", coverage: 75.0} = History.latest(project.id, "main", "App")
      assert History.latest(project.id, "main", "Missing") == nil

      assert [%{git_commit_sha: "a"}] =
               History.branch_points(project.id, "main", "App", until: ~N[2026-09-01 23:00:00])
    end

    test "list the schemes with full runs, most runs first", %{project: project, account: account} do
      run(project, account, %{git_commit_sha: "a"}, [1])
      run(project, account, %{git_commit_sha: "b"}, [1])
      run(project, account, %{git_commit_sha: "b", scheme: "Other"}, [1])
      run(project, account, %{git_commit_sha: "c", scheme: "Partial", partial: true}, [1])

      assert History.schemes(project.id, "main") == [%{scheme: "App", runs_count: 2}, %{scheme: "Other", runs_count: 1}]
    end
  end

  describe "branches/3" do
    test "gives every branch's newest full run with its distance from the default branch", %{
      project: project,
      account: account
    } do
      run(project, account, %{git_commit_sha: "a", ran_at: ~N[2026-09-01 10:00:00]}, [1, 1, 0, 0])
      run(project, account, %{git_commit_sha: "f1", git_branch: "feature", ran_at: ~N[2026-09-02 10:00:00]}, [1, 0, 0, 0])
      run(project, account, %{git_commit_sha: "f2", git_branch: "feature", ran_at: ~N[2026-09-03 10:00:00]}, [1, 1, 1, 0])
      run(project, account, %{git_commit_sha: "p", git_branch: "partial", partial: true}, [1, 1, 1, 1])

      assert [
               %{git_branch: "feature", git_commit_sha: "f2", coverage: 75.0, delta: 25.0},
               %{git_branch: "main", git_commit_sha: "a", coverage: 50.0, delta: +0.0}
             ] = History.branches(project, "App")
    end

    test "has no delta without a default branch run", %{project: project, account: account} do
      run(project, account, %{git_commit_sha: "f1", git_branch: "feature"}, [1, 0])
      assert [%{git_branch: "feature", delta: nil}] = History.branches(project, "App")
    end
  end

  describe "pull_requests/2 and pull_request_runs/3" do
    test "list the newest run per pull request and scheme, partial ones included", %{
      project: project,
      account: account
    } do
      pr = %{git_branch: "feature", is_pull_request: true, pull_request_number: 7, base_branch: "main"}

      run(project, account, Map.merge(pr, %{git_commit_sha: "p1", ran_at: ~N[2026-09-01 10:00:00]}), [1, 0])

      newest =
        run(project, account, Map.merge(pr, %{git_commit_sha: "p2", ran_at: ~N[2026-09-02 10:00:00], partial: true}), [
          1,
          1
        ])

      other =
        run(project, account, Map.merge(pr, %{git_commit_sha: "p2", scheme: "Other", ran_at: ~N[2026-09-02 09:00:00]}), [
          0,
          1
        ])

      run(
        project,
        account,
        %{
          git_branch: "fix",
          is_pull_request: true,
          pull_request_number: 8,
          git_commit_sha: "q",
          ran_at: ~N[2026-09-03 10:00:00]
        },
        [1, 1, 1, 1]
      )

      run(project, account, %{git_commit_sha: "m"}, [1])

      {rows, count} = History.pull_requests(project.id)

      assert count == 3

      assert Enum.map(rows, &{&1.pull_request_number, &1.scheme, &1.test_run_id, &1.partial, &1.coverage}) == [
               {8, "App", rows |> Enum.at(0) |> Map.get(:test_run_id), false, 100.0},
               {7, "App", newest.id, true, 100.0},
               {7, "Other", other.id, false, 50.0}
             ]

      assert {[%{pull_request_number: 7}], 3} = History.pull_requests(project.id, page: 2, page_size: 1)

      assert Enum.map(History.pull_request_runs(project.id, 7), &{&1.git_commit_sha, &1.scheme}) == [
               {"p2", "App"},
               {"p2", "Other"},
               {"p1", "App"}
             ]
    end
  end
end
