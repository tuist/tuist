defmodule Tuist.Tests.Coverage.HistoryTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Ecto.Query

  alias Tuist.Repo
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
    end

    test "chain a complete commit whatever it measured", %{project: project, account: account} do
      run(project, account, %{git_commit_sha: "a", ran_at: ~N[2026-09-01 10:00:00]}, [1, 0])
      run(project, account, %{git_commit_sha: "b", ran_at: ~N[2026-09-02 10:00:00], scheme: "Other"}, [1, 1])

      assert Enum.map(History.branch_points(project, "main"), & &1.git_commit_sha) == ["a"]

      Tuist.Tests.Coverage.Commits.signal_complete(project, "b")
      assert Enum.map(History.branch_points(project, "main"), & &1.git_commit_sha) == ["a", "b"]
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

  describe "refs/2" do
    setup %{project: project, account: account} do
      run(project, account, %{git_commit_sha: "m", ran_at: ~N[2026-09-01 10:00:00]}, [1, 1, 0, 0])

      run(
        project,
        account,
        %{git_commit_sha: "f", git_branch: "feature/widgets", ran_at: ~N[2026-09-02 10:00:00]},
        [1, 1, 1, 0]
      )

      run(
        project,
        account,
        %{
          git_commit_sha: "p",
          git_branch: "feature/gates",
          is_pull_request: true,
          pull_request_number: 42,
          base_branch: "main",
          ran_at: ~N[2026-09-03 10:00:00]
        },
        [1, 1, 1, 1]
      )

      :ok
    end

    test "lists a branch once, the most recently measured first, with the pull request it was pushed for", %{
      project: project
    } do
      page = History.refs(project)

      assert Enum.map(page.refs, &{&1.name, &1.pull_request_number, &1.coverage}) == [
               {"feature/gates", 42, 100.0},
               {"feature/widgets", 0, 75.0},
               {"main", 0, 50.0}
             ]

      assert [%{base_branch: "main", git_commit_sha: "p"} | _] = page.refs
    end

    test "lists a pull request whose runs named no branch under its number", %{project: project, account: account} do
      run(
        project,
        account,
        %{
          git_commit_sha: "n",
          git_branch: "",
          is_pull_request: true,
          pull_request_number: 77,
          ran_at: ~N[2026-09-05 10:00:00]
        },
        [1, 1, 1, 0]
      )

      assert %{name: "#77", pull_request_number: 77, git_branch: ""} =
               Enum.find(History.refs(project).refs, &(&1.pull_request_number == 77))
    end

    test "narrows them by branch name or pull request number, and pages", %{project: project} do
      assert Enum.map(History.refs(project, search: "widgets").refs, & &1.name) == ["feature/widgets"]
      # A branch is found by the number of the pull request it was pushed for.
      assert Enum.map(History.refs(project, search: "#42").refs, & &1.name) == ["feature/gates"]
      assert Enum.map(History.refs(project, search: "gates").refs, & &1.name) == ["feature/gates"]
      assert History.refs(project, search: "nothing").refs == []
    end

    test "pages from a cursor, newest first, each branch once", %{project: project, account: account} do
      # A newer commit of a branch listed further down moves it up, and it is
      # not listed again where its older commit was.
      run(
        project,
        account,
        %{git_commit_sha: "w2", git_branch: "feature/widgets", ran_at: ~N[2026-09-04 10:00:00]},
        [1, 0, 0, 0]
      )

      first = History.refs(project, page_size: 2)
      assert Enum.map(first.refs, &{&1.name, &1.git_commit_sha}) == [{"feature/widgets", "w2"}, {"feature/gates", "p"}]
      assert first.has_next_page?
      refute first.has_previous_page?

      second = History.refs(project, page_size: 2, after: first.end_cursor)
      assert Enum.map(second.refs, & &1.name) == ["main"]
      refute second.has_next_page?
      assert second.has_previous_page?

      back = History.refs(project, page_size: 2, before: second.start_cursor)
      assert Enum.map(back.refs, & &1.name) == ["feature/widgets", "feature/gates"]
      refute back.has_previous_page?
      assert back.has_next_page?
    end

    test "shows a commit whose runs skipped tests by its reported figure, only its confirmed part when some were not carried",
         %{project: project} do
      Repo.update_all(
        from(c in CoverageCommit, where: c.project_id == ^project.id and c.git_commit_sha == "f"),
        set: [reported_kind: "partial", reported_covered_lines: 5, reported_executable_lines: 8]
      )

      assert %{coverage: 62.5, covered_lines: 5, executable_lines: 8, confirmed: false, measured_coverage: 75.0} =
               Enum.find(History.refs(project).refs, &(&1.git_commit_sha == "f"))

      assert %{confirmed: true} = Enum.find(History.refs(project).refs, &(&1.git_commit_sha == "m"))
    end

    test "lists a branch by its newest commit up to the period's end", %{project: project, account: account} do
      run(
        project,
        account,
        %{git_commit_sha: "w2", git_branch: "feature/widgets", ran_at: ~N[2026-09-04 10:00:00]},
        [1, 0, 0, 0]
      )

      assert [%{git_commit_sha: "f", coverage: 75.0}] =
               History.refs(project, until: ~U[2026-09-02 23:59:59Z], search: "widgets").refs
    end

    test "keeps to the branches measured in the period", %{project: project} do
      assert Enum.map(History.refs(project, since: ~U[2026-09-02 00:00:00Z]).refs, & &1.name) == [
               "feature/gates",
               "feature/widgets"
             ]

      assert Enum.map(History.refs(project, until: ~U[2026-09-01 23:59:59Z]).refs, & &1.name) == ["main"]
    end
  end
end
