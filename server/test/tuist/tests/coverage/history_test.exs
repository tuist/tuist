defmodule Tuist.Tests.Coverage.HistoryTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.CoverageCommit
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

  # Published commits of the labelled `main`, one per timestamp, each
  # covering its index of 100 lines; complete unless listed in `pending`.
  defp publish(project, timestamps, pending \\ []) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      timestamps
      |> Enum.with_index()
      |> Enum.map(fn {at, index} ->
        %{
          project_id: project.id,
          git_commit_sha: "c#{index}",
          git_branch: "main",
          committed_at: at,
          ran_at: at,
          covered_lines: index,
          executable_lines: 100,
          complete: "c#{index}" not in pending,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(CoverageCommit, rows)
  end

  defp shas(points), do: Enum.map(points, & &1.git_commit_sha)

  @epoch ~U[2026-01-05 00:00:00.000000Z]

  describe "branch_history/3 and branch_points/3" do
    test "list the commits measured on the branch in the order they were measured when the graph has no head", %{
      project: project,
      account: account
    } do
      run(project, account, %{git_commit_sha: "a", ran_at: ~N[2026-09-01 10:00:00]}, [1, 0, 0, 0])
      run(project, account, %{git_commit_sha: "b", ran_at: ~N[2026-09-02 10:00:00]}, [1, 1, 0, 0])
      run(project, account, %{git_commit_sha: "b", ran_at: ~N[2026-09-02 11:00:00]}, [1, 1, 1, 0])
      run(project, account, %{git_commit_sha: "c", ran_at: ~N[2026-09-03 10:00:00], partial: true}, [1, 1, 1, 1])
      run(project, account, %{git_commit_sha: "c", ran_at: ~N[2026-09-03 10:00:00], scheme: "Other"}, [1, 1, 1, 1])
      run(project, account, %{git_commit_sha: "d", ran_at: ~N[2026-09-04 10:00:00], git_branch: "feature"}, [0, 0, 0, 0])

      history = History.branch_history(project, "main")
      assert history.ordered_by == :time

      # b unions its two runs; c measured another set (App partially, plus
      # Other) so it does not chain.
      assert Enum.map(history.commits, &{&1.git_commit_sha, &1.coverage, &1.chained}) ==
               [{"c", 100.0, false}, {"b", 75.0, true}, {"a", 25.0, true}]

      assert Enum.map(History.branch_points(project, "main"), &{&1.git_commit_sha, &1.coverage}) ==
               [{"a", 25.0}, {"b", 75.0}]
    end

    test "walk the graph from the branch's head, unmeasured commits included", %{
      project: project,
      account: account
    } do
      # main: a → b → c → m, where m merges e (off b); feature f off c.
      CoverageFixtures.seed_history(
        account,
        [
          CoverageFixtures.commit("a", [], 0),
          CoverageFixtures.commit("b", ["a"], 1),
          CoverageFixtures.commit("c", ["b"], 2),
          CoverageFixtures.commit("e", ["b"], 3),
          CoverageFixtures.commit("m", ["c", "e"], 4),
          CoverageFixtures.commit("f", ["c"], 5)
        ],
        branch_heads: [{"main", "m"}, {"feature", "f"}]
      )

      run(project, account, %{git_commit_sha: "a"}, [1, 0, 0, 0])
      run(project, account, %{git_commit_sha: "e", git_branch: "side"}, [1, 1, 1, 1])
      run(project, account, %{git_commit_sha: "m"}, [1, 1, 0, 0])
      # Measured on the pull request, on main's chain once merged.
      run(project, account, %{git_commit_sha: "f", git_branch: "feature"}, [1, 1, 1, 0])

      history = History.branch_history(project, "main")
      assert history.ordered_by == :graph

      assert Enum.map(history.commits, &{&1.git_commit_sha, &1.depth, &1.measured}) ==
               [{"m", 0, true}, {"c", 1, false}, {"b", 2, false}, {"a", 3, true}]

      assert Enum.map(History.branch_points(project, "main"), &{&1.git_commit_sha, &1.coverage}) ==
               [{"a", 25.0}, {"m", 50.0}]

      # The feature branch holds what it added, not the history it was cut
      # from, which `main` above already lists.
      assert Enum.map(History.branch_history(project, "feature").commits, & &1.git_commit_sha) == ["f"]
    end

    test "cut a branch at its merge base with the default branch", %{project: project, account: account} do
      # main: a → b → c; feature: two commits off b, and a branch already
      # merged into main.
      CoverageFixtures.seed_history(
        account,
        [
          CoverageFixtures.commit("a", [], 0),
          CoverageFixtures.commit("b", ["a"], 1),
          CoverageFixtures.commit("c", ["b"], 2),
          CoverageFixtures.commit("f1", ["b"], 3),
          CoverageFixtures.commit("f2", ["f1"], 4)
        ],
        branch_heads: [{"main", "c"}, {"feature", "f2"}, {"merged", "b"}]
      )

      for sha <- ~w(a b c), do: run(project, account, %{git_commit_sha: sha}, [1, 1, 0, 0])
      for sha <- ~w(f1 f2), do: run(project, account, %{git_commit_sha: sha, git_branch: "feature"}, [1, 1, 0, 0])

      assert Enum.map(History.branch_history(project, "feature").commits, & &1.git_commit_sha) == ["f2", "f1"]

      # The oldest commit kept still compares with the commit the branch left,
      # which the cut walk no longer holds.
      assert Enum.map(History.branch_history(project, "feature").commits, & &1.change) == [0.0, 0.0]

      # The default branch is the one the others are cut against, so it keeps
      # its whole history.
      assert Enum.map(History.branch_history(project, "main").commits, & &1.git_commit_sha) == ["c", "b", "a"]

      # A branch the default one already contains has no divergence left in
      # the graph, so it holds the commits its runs were labelled with — none
      # here, and `b` once a run says so.
      assert Enum.map(History.branch_history(project, "merged").commits, & &1.git_commit_sha) == []

      run(project, account, %{git_commit_sha: "b", git_branch: "merged"}, [1, 1, 1, 0])

      assert Enum.map(History.branch_history(project, "merged").commits, & &1.git_commit_sha) == ["b"]
    end

    test "read a fast-forwarded branch as what ran on it", %{project: project, account: account} do
      # `feature` is built on `a` and `main` is fast-forwarded onto it, so both
      # branches end at the same commit and the graph holds no merge commit.
      CoverageFixtures.seed_history(
        account,
        [
          CoverageFixtures.commit("a", [], 0),
          CoverageFixtures.commit("f1", ["a"], 1),
          CoverageFixtures.commit("f2", ["f1"], 2)
        ],
        branch_heads: [{"main", "f2"}, {"feature", "f2"}]
      )

      run(project, account, %{git_commit_sha: "a"}, [1, 0, 0, 0])
      run(project, account, %{git_commit_sha: "f1", git_branch: "feature"}, [1, 1, 0, 0])
      run(project, account, %{git_commit_sha: "f2", git_branch: "feature"}, [1, 1, 1, 0])

      # The commits are `main`'s history now, and they say so.
      assert Enum.map(History.branch_history(project, "main").commits, & &1.git_commit_sha) == ["f2", "f1", "a"]

      # They were measured on the branch, so they stay with it too, without
      # dragging `main`'s history along.
      assert Enum.map(History.branch_history(project, "feature").commits, & &1.git_commit_sha) == ["f2", "f1"]
    end

    test "draw the trend from the ref's commits made in the period, however far back", %{
      project: project,
      account: account
    } do
      # One commit a day, 300 days: past the 200 commits a branch's list reads.
      commits =
        for day <- 0..299 do
          sha = "c#{day}"
          parents = if day == 0, do: [], else: ["c#{day - 1}"]
          CoverageFixtures.commit(sha, parents, day * 24 * 60)
        end

      CoverageFixtures.seed_history(account, commits, branch_heads: [{"main", "c299"}])

      for day <- [0, 10, 250, 299] do
        run(project, account, %{git_commit_sha: "c#{day}"}, [1, 0])
      end

      points = History.branch_points(project, "main")
      assert Enum.map(points, & &1.git_commit_sha) == ["c0", "c10", "c250", "c299"]

      since = DateTime.add(~U[2026-09-01 00:00:00Z], 5, :day)

      assert project |> History.branch_points("main", since: since) |> Enum.map(& &1.git_commit_sha) == [
               "c10",
               "c250",
               "c299"
             ]
    end

    test "page a branch's commits from a cursor, both ways", %{project: project, account: account} do
      commits =
        for index <- 0..6 do
          CoverageFixtures.commit("c#{index}", if(index == 0, do: [], else: ["c#{index - 1}"]), index)
        end

      CoverageFixtures.seed_history(account, commits, branch_heads: [{"main", "c6"}])
      for index <- [1, 3, 4, 6], do: run(project, account, %{git_commit_sha: "c#{index}"}, [1, 0])

      first = History.commit_cursor_page(project, "main", page_size: 3)
      assert Enum.map(first.commits, & &1.git_commit_sha) == ["c6", "c5", "c4"]
      assert {first.has_previous_page?, first.has_next_page?} == {false, true}
      # c4 compares with c3, below the page.
      assert Enum.map(first.commits, & &1.change) == [+0.0, nil, +0.0]

      second = History.commit_cursor_page(project, "main", page_size: 3, after: first.end_cursor)
      assert Enum.map(second.commits, & &1.git_commit_sha) == ["c3", "c2", "c1"]
      assert {second.has_previous_page?, second.has_next_page?} == {true, true}

      last = History.commit_cursor_page(project, "main", page_size: 3, after: second.end_cursor)
      assert Enum.map(last.commits, & &1.git_commit_sha) == ["c0"]
      assert {last.has_previous_page?, last.has_next_page?} == {true, false}

      back = History.commit_cursor_page(project, "main", page_size: 3, before: second.start_cursor)
      assert Enum.map(back.commits, & &1.git_commit_sha) == ["c6", "c5", "c4"]
      assert {back.has_previous_page?, back.has_next_page?} == {false, true}
    end

    test "page a branch's commits of one status, or whose SHA starts with a search, from a cursor", %{
      project: project,
      account: account
    } do
      commits =
        for index <- 0..6 do
          CoverageFixtures.commit("c#{index}", if(index == 0, do: [], else: ["c#{index - 1}"]), index)
        end

      CoverageFixtures.seed_history(account, commits, branch_heads: [{"main", "c6"}])
      for index <- [1, 3, 4, 6], do: run(project, account, %{git_commit_sha: "c#{index}"}, [1, 0])
      Commits.signal_complete(project, "c4")

      first = History.commit_cursor_page(project, "main", page_size: 2, status: "not-measured")
      assert Enum.map(first.commits, & &1.git_commit_sha) == ["c5", "c2"]
      assert {first.has_previous_page?, first.has_next_page?} == {false, true}

      second = History.commit_cursor_page(project, "main", page_size: 2, status: "not-measured", after: first.end_cursor)
      assert Enum.map(second.commits, & &1.git_commit_sha) == ["c0"]
      assert {second.has_previous_page?, second.has_next_page?} == {true, false}

      back =
        History.commit_cursor_page(project, "main", page_size: 2, status: "not-measured", before: second.start_cursor)

      assert Enum.map(back.commits, & &1.git_commit_sha) == ["c5", "c2"]
      assert {back.has_previous_page?, back.has_next_page?} == {false, true}

      assert Enum.map(History.commit_cursor_page(project, "main", status: "complete").commits, & &1.git_commit_sha) ==
               ["c4"]

      assert Enum.map(History.commit_cursor_page(project, "main", status: "pending").commits, & &1.git_commit_sha) ==
               ["c6", "c3", "c1"]

      assert Enum.map(History.commit_cursor_page(project, "main", search: "C3 ").commits, & &1.git_commit_sha) == ["c3"]
      assert History.commit_cursor_page(project, "main", search: "c3", status: "complete").commits == []
    end

    test "page a branch's labelled commits from a cursor when its ref owns none", %{
      project: project,
      account: account
    } do
      for {sha, hour} <- [{"a", 1}, {"b", 2}, {"c", 3}] do
        run(project, account, %{git_commit_sha: sha, ran_at: NaiveDateTime.new!(~D[2026-09-01], Time.new!(hour, 0, 0))}, [
          1,
          0
        ])
      end

      first = History.commit_cursor_page(project, "main", page_size: 2)
      assert first.ordered_by == :time
      assert Enum.map(first.commits, & &1.git_commit_sha) == ["c", "b"]
      assert first.has_next_page?

      second = History.commit_cursor_page(project, "main", page_size: 2, after: first.end_cursor)
      assert Enum.map(second.commits, & &1.git_commit_sha) == ["a"]
      assert {second.has_previous_page?, second.has_next_page?} == {true, false}

      searched = History.commit_cursor_page(project, "main", page_size: 2, search: "b")
      assert Enum.map(searched.commits, & &1.git_commit_sha) == ["b"]
      assert {searched.has_previous_page?, searched.has_next_page?} == {false, false}

      # Labelled commits are all measured.
      assert History.commit_cursor_page(project, "main", status: "not-measured").commits == []

      assert Enum.map(History.commit_cursor_page(project, "main", status: "pending").commits, & &1.git_commit_sha) == [
               "c",
               "b",
               "a"
             ]
    end

    test "chain a complete commit whatever it measured", %{project: project, account: account} do
      run(project, account, %{git_commit_sha: "a", ran_at: ~N[2026-09-01 10:00:00]}, [1, 0])
      run(project, account, %{git_commit_sha: "b", ran_at: ~N[2026-09-02 10:00:00], scheme: "Other"}, [1, 1])

      assert Enum.map(History.branch_points(project, "main"), & &1.git_commit_sha) == ["a"]

      Commits.signal_complete(project, "b")
      assert Enum.map(History.branch_points(project, "main"), & &1.git_commit_sha) == ["a", "b"]
    end
  end

  describe "trend_points/3" do
    test "draws the complete commits along the graph, leaving out the pending ones", %{
      project: project,
      account: account
    } do
      CoverageFixtures.seed_history(
        account,
        [
          CoverageFixtures.commit("a", [], 0),
          CoverageFixtures.commit("b", ["a"], 1),
          CoverageFixtures.commit("c", ["b"], 2)
        ],
        branch_heads: [{"main", "c"}]
      )

      run(project, account, %{git_commit_sha: "a"}, [1, 0, 0, 0])
      run(project, account, %{git_commit_sha: "b"}, [1, 1, 0, 0])
      run(project, account, %{git_commit_sha: "c"}, [1, 1, 1, 0])
      Commits.signal_complete(project, "a")
      Commits.signal_complete(project, "c")

      assert Enum.map(History.trend_points(project, "main"), &{&1.git_commit_sha, &1.coverage}) ==
               [{"a", 25.0}, {"c", 75.0}]
    end

    test "draws every complete commit when they fit", %{project: project} do
      publish(project, Enum.map(0..40, &DateTime.add(@epoch, &1, :hour)), ["c40"])

      assert shas(History.trend_points(project, "main")) == Enum.map(0..39, &"c#{&1}")
    end

    test "draws each day's latest complete commit when the commits do not fit", %{project: project} do
      publish(project, Enum.map(0..40, &DateTime.add(@epoch, &1, :hour)))

      assert shas(History.trend_points(project, "main")) == ["c23", "c40"]
    end

    test "draws each week's latest complete commit when the days do not fit", %{project: project} do
      publish(project, Enum.map(0..40, &DateTime.add(@epoch, &1, :day)))

      assert shas(History.trend_points(project, "main")) == ["c6", "c13", "c20", "c27", "c34", "c40"]
    end

    test "draws each month's latest complete commit, the most recent 40, when the weeks do not fit", %{
      project: project
    } do
      publish(project, Enum.map(0..40, &DateTime.add(@epoch, &1 * 8, :day)))
      points = History.trend_points(project, "main")
      assert length(points) == 11
      assert List.last(points).git_commit_sha == "c40"

      Repo.delete_all(CoverageCommit)
      publish(project, Enum.map(0..41, &DateTime.add(@epoch, &1 * 31, :day)))
      points = History.trend_points(project, "main")
      assert length(points) == 40
      assert {List.first(points).git_commit_sha, List.last(points).git_commit_sha} == {"c2", "c41"}
    end

    test "bounds the commits by the period", %{project: project} do
      publish(project, Enum.map(0..2, &DateTime.add(@epoch, &1, :day)))

      assert shas(History.trend_points(project, "main", since: DateTime.add(@epoch, 1, :day))) == ["c1", "c2"]
    end
  end

  describe "branches/2" do
    test "lists the branches whose runs never named a pull request, the default branch first, then the most recently measured",
         %{project: project, account: account} do
      run(project, account, %{git_commit_sha: "a", git_branch: "release", ran_at: ~N[2026-09-01 10:00:00]}, [1, 0])
      run(project, account, %{git_commit_sha: "b", git_branch: "develop", ran_at: ~N[2026-09-03 10:00:00]}, [1, 0])
      run(project, account, %{git_commit_sha: "c", git_branch: "feature", ran_at: ~N[2026-09-04 10:00:00]}, [1, 0])

      run(
        project,
        account,
        %{
          git_commit_sha: "d",
          git_branch: "feature",
          is_pull_request: true,
          pull_request_number: 7,
          ran_at: ~N[2026-09-02 10:00:00]
        },
        [1, 0]
      )

      assert History.branches(project) == ["main", "develop", "release"]

      run(project, account, %{git_commit_sha: "e", ran_at: ~N[2026-09-02 10:00:00]}, [1, 0])
      assert History.branches(project) == ["main", "develop", "release"]
      assert History.branches(project, limit: 1) == ["main", "develop"]
    end
  end

  describe "pull_request_commits/3" do
    test "lists the pull request's measured commits, newest first, with what measured them", %{
      project: project,
      account: account
    } do
      pr = %{git_branch: "feature", is_pull_request: true, pull_request_number: 7, base_branch: "main"}

      run(project, account, Map.merge(pr, %{git_commit_sha: "p1", ran_at: ~N[2026-09-01 10:00:00]}), [1, 0])

      run(project, account, Map.merge(pr, %{git_commit_sha: "p2", ran_at: ~N[2026-09-02 10:00:00], partial: true}), [1, 1])

      run(project, account, Map.merge(pr, %{git_commit_sha: "p2", scheme: "Other", ran_at: ~N[2026-09-02 09:00:00]}), [
        0,
        1
      ])

      run(
        project,
        account,
        %{git_branch: "fix", is_pull_request: true, pull_request_number: 8, git_commit_sha: "q"},
        [1, 1, 1, 1]
      )

      run(project, account, %{git_commit_sha: "m"}, [1])

      assert [
               %{
                 git_commit_sha: "p2",
                 coverage: 100.0,
                 schemes: ["App", "Other"],
                 partial_schemes: ["App"],
                 base_branch: "main"
               },
               %{git_commit_sha: "p1", coverage: 50.0, schemes: ["App"], partial_schemes: []}
             ] = History.pull_request_commits(project.id, 7)

      assert [%{git_commit_sha: "q"}] = History.pull_request_commits(project.id, 8)
      assert History.pull_request_commits(project.id, 9) == []
    end
  end
end
