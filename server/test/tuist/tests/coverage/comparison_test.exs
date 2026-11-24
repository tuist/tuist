defmodule Tuist.Tests.Coverage.ComparisonTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Repo
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.VCS.Workers.CommentWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # main: a → b → m, where m merges the feature branch a → f1, and the pull
  # request's commit p sits on m. f1 is the closest ancestor of m by any
  # path, but it's on a branch merged into the base, not the base branch.
  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account

    project =
      ProjectsFixtures.project_fixture(
        account_id: account.id,
        default_branch: "main",
        vcs_connection: [repository_full_handle: "tuist/app"]
      )

    CoverageFixtures.seed_history(
      account,
      [
        CoverageFixtures.commit("a", [], 0),
        CoverageFixtures.commit("b", ["a"], 1),
        CoverageFixtures.commit("f1", ["a"], 2),
        CoverageFixtures.commit("m", ["b", "f1"], 3),
        CoverageFixtures.commit("p", ["m"], 4)
      ],
      branch_heads: [feature: "f1", main: "m"]
    )

    %{account: account, project: project}
  end

  defp file(path, counts, target), do: CoverageFixtures.file(path, counts, targets: [target])

  defp measure(project, account, sha, files, attrs \\ %{}) do
    CoverageFixtures.run_with_coverage(project, account, files, Map.merge(%{git_commit_sha: sha}, attrs))
  end

  defp pull_request(project, account, files, attrs \\ %{}) do
    measure(
      project,
      account,
      "p",
      files,
      Map.merge(
        %{
          git_branch: "feature-2",
          git_ref: "refs/pull/7/merge",
          is_pull_request: true,
          pull_request_number: 7,
          base_branch: "main",
          merge_base_sha: "m"
        },
        attrs
      )
    )

    Commits.signal_complete(project, "p")
  end

  test "falls back to the nearest complete commit on the base's first parents, then to the base itself", %{
    project: project,
    account: account
  } do
    measure(project, account, "a", [file("Sources/Core.swift", [1, 0], "Core"), file("Sources/UI.swift", [1, 1], "UI")])
    Commits.signal_complete(project, "a")

    # Closer to m by the merge, and complete, but on the merged-in branch.
    measure(
      project,
      account,
      "f1",
      [file("Sources/Core.swift", [1, 1], "Core"), file("Sources/UI.swift", [1, 1], "UI")],
      %{git_branch: "feature"}
    )

    Commits.signal_complete(project, "f1")

    # On the base branch and closer, but its pipeline never signalled.
    measure(project, account, "b", [file("Sources/Core.swift", [0, 0], "Core"), file("Sources/UI.swift", [0, 0], "UI")])

    pull_request(project, account, [
      file("Sources/Core.swift", [1, 1], "Core"),
      file("Sources/UI.swift", [1, 1], "UI"),
      file("Sources/New.swift", [0, 0], "New")
    ])

    assert %{
             status: :complete,
             requested_base_sha: "m",
             requested_base_measured: false,
             base: %{git_commit_sha: "a", distance: 2, coverage: 75.0},
             head: %{coverage: 66.7},
             change: -8.3
           } = comparison = Comparison.compare(project, "p")

    assert comparison.targets |> Enum.map(&{&1.name, &1.coverage, &1.change}) |> Enum.sort() == [
             {"Core", 100.0, 50.0},
             {"New", 0.0, nil},
             {"UI", 100.0, 0.0}
           ]

    assert Enum.map(comparison.changed_files, &{&1.path, &1.change}) == [{"Sources/Core.swift", 50.0}]

    # Once b completes it's the nearest; once m does, the base itself.
    Commits.signal_complete(project, "b")
    assert %{base: %{git_commit_sha: "b", distance: 1}, change: 66.7} = Comparison.compare(project, "p")

    measure(project, account, "m", [file("Sources/Core.swift", [1, 1], "Core"), file("Sources/UI.swift", [1, 0], "UI")])
    # Measured but not signalled: still b, though m now has a figure of its own.
    assert %{base: %{git_commit_sha: "b"}, requested_base_measured: true} = Comparison.compare(project, "p")

    Commits.signal_complete(project, "m")
    assert %{base: %{git_commit_sha: "m", distance: 0}, change: -8.3} = Comparison.compare(project, "p")
  end

  test "leaves the change unknown when no commit on the base's first parents is complete", %{
    project: project,
    account: account
  } do
    measure(project, account, "f1", [file("Sources/Core.swift", [1, 1], "Core")], %{git_branch: "feature"})
    Commits.signal_complete(project, "f1")
    pull_request(project, account, [file("Sources/Core.swift", [1, 0], "Core")])

    assert %{status: :complete, requested_base_sha: "m", base: nil, change: nil, changed_files: []} =
             comparison = Comparison.compare(project, "p")

    assert [%{name: "Core", coverage: 50.0, change: nil}] = comparison.targets
  end

  test "takes the base from the commit graph when no run reported a merge base", %{
    project: project,
    account: account
  } do
    measure(project, account, "m", [file("Sources/Core.swift", [1, 1], "Core")])
    Commits.signal_complete(project, "m")
    pull_request(project, account, [file("Sources/Core.swift", [1, 0], "Core")], %{merge_base_sha: ""})

    assert %{requested_base_sha: "m", base: %{git_commit_sha: "m"}, change: -50.0} = Comparison.compare(project, "p")
  end

  test "takes the base the runs reported, even one the commit graph doesn't have yet", %{
    project: project,
    account: account
  } do
    pull_request(project, account, [file("Sources/Core.swift", [1, 0], "Core")], %{merge_base_sha: "unknown"})

    assert %{requested_base_sha: "unknown", base: nil, change: nil} = Comparison.compare(project, "p")
  end

  test "compares only a complete commit", %{project: project, account: account} do
    assert Comparison.compare(project, "p") == nil

    measure(project, account, "p", [file("Sources/Core.swift", [1, 0], "Core")])
    assert %{status: :in_progress, head: %{coverage: 50.0}} = comparison = Comparison.compare(project, "p")
    refute Map.has_key?(comparison, :base)

    # A scheme only a dirty CI run measured leaves the figure a lower bound.
    measure(project, account, "p", [file("Sources/Other.swift", [1], "Other")], %{scheme: "Other", git_dirty: true})
    Commits.signal_complete(project, "p")
    assert %{status: :incomplete} = Comparison.compare(project, "p")
  end

  test "a pull request commit folded complete queues its comment, once per pending job", %{
    project: project,
    account: account
  } do
    measure(project, account, "a", [file("Sources/Core.swift", [1, 0], "Core")])
    Commits.signal_complete(project, "a")
    refute_enqueued(worker: CommentWorker, args: %{"git_commit_sha" => "a"})

    # Without the comment the run's upload queued, so the job is the fold's.
    measure(project, account, "p", [file("Sources/Core.swift", [1, 1], "Core")], %{
      git_ref: "refs/pull/7/merge",
      is_pull_request: true,
      pull_request_number: 7,
      base_branch: "main"
    })

    Repo.delete_all(Oban.Job)
    Commits.recompute(project, "p")
    refute_enqueued(worker: CommentWorker, args: %{"git_commit_sha" => "p"})

    Commits.signal_complete(project, "p")
    Commits.recompute(project, "p")

    assert [%{args: args}] = all_enqueued(worker: CommentWorker, args: %{"git_commit_sha" => "p"})

    assert args == %{
             "git_commit_sha" => "p",
             "git_ref" => "refs/pull/7/merge",
             "git_remote_url_origin" => "https://github.com/tuist/app",
             "project_id" => project.id
           }
  end
end
