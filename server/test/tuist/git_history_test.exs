defmodule Tuist.GitHistoryTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.GitHistory
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{account: account, project: project, repository: GitHistory.repository_id(account.id, "git@github.com:acme/app.git")}
  end

  # A linear history a → b → c → d (d newest) with a side branch e off b,
  # and a merge commit m of e into d.
  defp commit(sha, parents, minutes) do
    %{sha: sha, parents: parents, committed_at: DateTime.add(~U[2026-09-01 00:00:00Z], minutes * 60, :second)}
  end

  defp seed(repository) do
    GitHistory.record_commits(repository, "sha1", [
      commit("a", [], 0),
      commit("b", ["a"], 1),
      commit("c", ["b"], 2),
      commit("d", ["c"], 3),
      commit("e", ["b"], 4),
      commit("m", ["d", "e"], 5)
    ])
  end

  describe "repositories" do
    test "key remotes by host, owner and name whatever their spelling" do
      for url <- [
            "git@github.com:Acme/App.git",
            "ssh://git@github.com/acme/app.git",
            "https://x-access-token:secret@github.com/acme/app",
            "https://github.com/acme/app/"
          ] do
        assert GitHistory.repository_key(url) == "github.com/acme/app", url
      end

      assert GitHistory.repository_key("") == nil
      assert GitHistory.repository_key("/Users/me/app") == nil
      assert GitHistory.repository_key(nil) == nil
    end

    test "are created once per account and remote", %{account: account, repository: repository} do
      assert GitHistory.repository_id(account.id, "https://github.com/acme/app.git") == repository
      assert GitHistory.repository_id(account.id, "https://github.com/acme/other") != repository
      assert GitHistory.repository_id(account.id, "not a remote") == nil

      other = AccountsFixtures.user_fixture(preload: [:account]).account
      assert GitHistory.repository_id(other.id, "git@github.com:acme/app.git") != repository
    end

    test "the connected repository maps to the same key", %{account: account} do
      project =
        [account_id: account.id, vcs_connection: [repository_full_handle: "acme/app"]]
        |> ProjectsFixtures.project_fixture()
        |> Tuist.Repo.preload(:vcs_connection)

      assert GitHistory.repository_id_for_connection(project) ==
               GitHistory.repository_id(account.id, "git@github.com:acme/app.git")

      assert GitHistory.repository_id_for_connection(%{project | vcs_connection: nil}) == nil
    end
  end

  describe "record_commits/3 and missing_shas/2" do
    test "stores commits once, with generation numbers from their parents", %{repository: repository} do
      seed(repository)

      assert GitHistory.missing_shas(repository, ["a", "d", "zzz"]) == ["zzz"]
      assert GitHistory.known?(repository, "c")

      # Repeating an upload changes nothing.
      assert GitHistory.record_commits(repository, "sha1", [commit("d", ["c"], 3)]) == :ok
      assert GitHistory.missing_shas(repository, ["d"]) == []

      generations =
        Tuist.Repo.all(from(c in GitHistory.Commit, where: c.repository_id == ^repository, select: {c.sha, c.generation}))

      assert Map.new(generations) == %{"a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 3, "m" => 5}
    end

    test "a parent outside the window still gets an edge and counts as generation 0", %{repository: repository} do
      GitHistory.record_commits(repository, "sha1", [commit("x", ["outside"], 0)])

      assert [{"x", 0}] = GitHistory.ancestors(repository, "x")
      assert GitHistory.missing_shas(repository, ["outside"]) == ["outside"]
    end
  end

  describe "ancestry" do
    test "walks parents with the shortest depth per commit", %{repository: repository} do
      seed(repository)
      assert GitHistory.ancestors(repository, "d") == [{"d", 0}, {"c", 1}, {"b", 2}, {"a", 3}]
      assert GitHistory.ancestors(repository, "d", max_depth: 1) == [{"d", 0}, {"c", 1}]
    end

    test "follows first parents only along a chain, so a merged branch stays out", %{repository: repository} do
      seed(repository)

      assert Enum.map(GitHistory.first_parent_chain(repository, "m"), &{elem(&1, 0), elem(&1, 1)}) ==
               [{"m", 0}, {"d", 1}, {"c", 2}, {"b", 3}, {"a", 4}]

      assert [{"m", 0, %DateTime{}} | _] = GitHistory.first_parent_chain(repository, "m", max_depth: 1)
      assert GitHistory.first_parent(repository, "m") == "d"
      assert GitHistory.first_parent(repository, "a") == nil
      assert GitHistory.first_parent(repository, "unknown") == nil
    end

    test "finds the nearest candidate ancestor, the commit itself included", %{repository: repository} do
      seed(repository)
      assert GitHistory.nearest_ancestor(repository, "d", ["a", "b"]) == {"b", 2}
      assert GitHistory.nearest_ancestor(repository, "d", ["d"]) == {"d", 0}
      assert GitHistory.nearest_ancestor(repository, "d", ["e"]) == nil
      assert GitHistory.nearest_ancestor(repository, "d", []) == nil
      assert GitHistory.ancestor?(repository, "a", "e")
      refute GitHistory.ancestor?(repository, "c", "e")
    end

    test "never takes a candidate from another repository", %{account: account, repository: repository} do
      other = GitHistory.repository_id(account.id, "https://github.com/acme/other")
      seed(repository)
      GitHistory.record_commits(other, "sha1", [commit("d", [], 0)])

      assert GitHistory.nearest_ancestor(other, "d", ["c"]) == nil
    end

    test "computes a merge base from the graph", %{repository: repository} do
      seed(repository)
      assert GitHistory.merge_base(repository, "d", "e") == "b"
      assert GitHistory.merge_base(repository, "d", "c") == "c"
      assert GitHistory.merge_base(repository, "d", "unknown") == nil
    end
  end

  describe "branch heads" do
    test "keep the newest sha per branch and list the branch's commits from it", %{repository: repository} do
      seed(repository)
      GitHistory.record_branch_head(repository, "main", "c", "main")
      GitHistory.record_branch_head(repository, "main", "m", "main")
      GitHistory.record_branch_head(repository, "", "d", "main")

      assert GitHistory.branch_head(repository, "main") == "m"
      assert GitHistory.branch_head(repository, "") == nil
      main = GitHistory.ref(repository, "main")
      assert Enum.map(GitHistory.ref_commits(main.id), &elem(&1, 0)) == ["m", "d", "c", "b", "a"]
      assert GitHistory.ref(repository, "feature") == nil
    end

    test "stay put when an older commit's job is re-run", %{repository: repository} do
      seed(repository)
      GitHistory.record_branch_head(repository, "main", "d", "main")
      GitHistory.record_branch_head(repository, "main", "c", "main")

      assert GitHistory.branch_head(repository, "main") == "d"
      assert {_ref_id, 4} = GitHistory.position(repository, "d")
    end
  end

  describe "refs" do
    # Each ref's own commits, oldest first, with their positions.
    defp owned(repository, name) do
      case GitHistory.ref(repository, name) do
        nil -> []
        ref -> ref.id |> GitHistory.ref_commits() |> Enum.reverse() |> Enum.map(&{elem(&1, 0), elem(&1, 1)})
      end
    end

    test "number the default branch's first-parent history and append to it", %{repository: repository} do
      seed(repository)
      GitHistory.advance_ref(repository, "main", nil, "d")
      assert owned(repository, "main") == [{"a", 1}, {"b", 2}, {"c", 3}, {"d", 4}]

      # The merge commit joins; the merged commit stays off the default branch.
      GitHistory.advance_ref(repository, "main", nil, "m")
      assert owned(repository, "main") == [{"a", 1}, {"b", 2}, {"c", 3}, {"d", 4}, {"m", 5}]
      assert GitHistory.position(repository, "e") == nil
    end

    test "fork a pull request from the default branch, and rebase it", %{repository: repository} do
      seed(repository)

      GitHistory.record_commits(repository, "sha1", [
        commit("p1", ["b"], 10),
        commit("p2", ["p1"], 11),
        commit("r1", ["d"], 12),
        commit("r2", ["r1"], 13)
      ])

      GitHistory.advance_ref(repository, "main", nil, "d")
      GitHistory.advance_ref(repository, "pull/1", "main", "p2")

      pull = GitHistory.ref(repository, "pull/1")
      assert pull.fork_position == 2
      assert owned(repository, "pull/1") == [{"p1", 3}, {"p2", 4}]

      # Rebased onto d: the old commits are released and it forks higher up.
      GitHistory.advance_ref(repository, "pull/1", "main", "r2")
      assert GitHistory.ref(repository, "pull/1").fork_position == 4
      assert owned(repository, "pull/1") == [{"r1", 5}, {"r2", 6}]
      assert GitHistory.position(repository, "p1") == nil
    end

    test "release what a force-push rewrote, and never move back on a late report", %{repository: repository} do
      seed(repository)
      GitHistory.advance_ref(repository, "main", nil, "d")

      GitHistory.advance_ref(repository, "main", nil, "c", only_forward: true)
      assert GitHistory.branch_head(repository, "main") == "d"

      GitHistory.advance_ref(repository, "main", nil, "c")
      assert owned(repository, "main") == [{"a", 1}, {"b", 2}, {"c", 3}]
      assert GitHistory.position(repository, "d") == nil
    end

    test "take a fast-forwarded pull request's commits onto the default branch", %{repository: repository} do
      seed(repository)
      GitHistory.record_commits(repository, "sha1", [commit("p1", ["d"], 10), commit("p2", ["p1"], 11)])

      GitHistory.advance_ref(repository, "main", nil, "d")
      GitHistory.advance_ref(repository, "pull/1", "main", "p2")
      assert owned(repository, "pull/1") == [{"p1", 5}, {"p2", 6}]

      GitHistory.advance_ref(repository, "main", nil, "p2")
      assert owned(repository, "main") == [{"a", 1}, {"b", 2}, {"c", 3}, {"d", 4}, {"p1", 5}, {"p2", 6}]

      # The pull request forks again, above what it lost, and owns nothing.
      assert owned(repository, "pull/1") == []
      assert GitHistory.ref(repository, "pull/1").fork_position == 6
    end

    test "let a pull request seen before its base branch hand its commits over later", %{repository: repository} do
      seed(repository)
      GitHistory.record_commits(repository, "sha1", [commit("p1", ["d"], 10)])

      GitHistory.advance_ref(repository, "pull/1", "main", "p1")
      assert owned(repository, "pull/1") == [{"a", 1}, {"b", 2}, {"c", 3}, {"d", 4}, {"p1", 5}]

      GitHistory.advance_ref(repository, "main", nil, "d")
      assert owned(repository, "main") == [{"a", 1}, {"b", 2}, {"c", 3}, {"d", 4}]
      assert owned(repository, "pull/1") == [{"p1", 5}]
    end
  end

  describe "commit listings" do
    test "store a commit's files once, in parts, and answer what is tracked", %{
      project: project,
      repository: repository
    } do
      assert GitHistory.missing_listings(repository, ["c", "d"]) == ["c", "d"]

      GitHistory.record_listing(
        repository,
        "c",
        [
          %{path: "Package.resolved", git_blob_id: "resolved1", mode: 33_188},
          %{path: "Sources/A.swift", git_blob_id: "a1"}
        ],
        complete: false
      )

      refute GitHistory.listing_stored?(repository, "c")

      GitHistory.record_listing(repository, "c", [%{path: "Tests/Fixtures/x.json", git_blob_id: "x1"}], truncated: true)

      assert GitHistory.listing_stored?(repository, "c")
      assert GitHistory.missing_listings(repository, ["c", "d"]) == ["d"]
      assert %{files_count: 3, truncated: true} = GitHistory.listing(repository, "c")

      assert Enum.map(GitHistory.commit_files(repository, "c"), & &1.path) ==
               ["Package.resolved", "Sources/A.swift", "Tests/Fixtures/x.json"]

      assert GitHistory.blobs_at(repository, "c", ["Sources/A.swift", "Missing.swift"]) == %{"Sources/A.swift" => "a1"}

      assert GitHistory.tracked_files(project, repository, "c") == []

      {:ok, project} = Projects.update_project(project, %{tracked_file_globs: ["Package.resolved", "Tests/Fixtures/**"]})

      assert GitHistory.tracked_files(project, repository, "c") == [
               %{path: "Package.resolved", git_blob_id: "resolved1"},
               %{path: "Tests/Fixtures/x.json", git_blob_id: "x1"}
             ]

      # Repeating the upload changes nothing.
      GitHistory.record_listing(repository, "c", [%{path: "Sources/A.swift", git_blob_id: "a1"}], files_count: 3)
      assert %{files_count: 3, truncated: true} = GitHistory.listing(repository, "c")
    end
  end

  describe "settings/1 and prune/2" do
    test "layers project overrides over the defaults", %{project: project} do
      assert %{
               window_days: 365,
               window_commits: 5_000,
               provider_fallback: true,
               upload_batch_size: 500,
               tracked_file_globs: [],
               commit_file_limit: 50_000
             } = GitHistory.settings(project)

      {:ok, project} =
        Projects.update_project(project, %{
          git_history_window_days: 30,
          tracked_file_globs: ["Package.resolved"]
        })

      assert %{window_days: 30, provider_fallback: true, window_commits: 5_000, tracked_file_globs: ["Package.resolved"]} =
               GitHistory.settings(project)
    end

    test "drops commits older than the window and their parent edges", %{repository: repository} do
      old = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)

      GitHistory.record_commits(repository, "sha1", [
        %{sha: "old", parents: [], committed_at: old},
        %{sha: "new", parents: ["old"], committed_at: DateTime.utc_now()}
      ])

      assert {:ok, 1} = GitHistory.prune(repository, 1)
      assert GitHistory.missing_shas(repository, ["old", "new"]) == ["old"]
      # The edge from the kept commit to the dropped one marks the window's end.
      assert GitHistory.ancestors(repository, "new") == [{"new", 0}]
    end
  end
end
