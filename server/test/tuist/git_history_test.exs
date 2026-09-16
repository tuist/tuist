defmodule Tuist.GitHistoryTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.GitHistory
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    %{project: ProjectsFixtures.project_fixture()}
  end

  # A linear history a → b → c → d (d newest) with a side branch e off b.
  defp commit(sha, parents, minutes) do
    %{sha: sha, parents: parents, committed_at: DateTime.add(~U[2026-09-01 00:00:00Z], minutes * 60, :second)}
  end

  defp seed(project) do
    GitHistory.record_commits(project.id, "sha1", [
      commit("a", [], 0),
      commit("b", ["a"], 1),
      commit("c", ["b"], 2),
      commit("d", ["c"], 3),
      commit("e", ["b"], 4)
    ])
  end

  describe "record_commits/3 and missing_shas/2" do
    test "stores commits once, with generation numbers from their parents", %{project: project} do
      seed(project)

      assert GitHistory.missing_shas(project.id, ["a", "d", "zzz"]) == ["zzz"]
      assert GitHistory.known?(project.id, "c")

      # Repeating an upload changes nothing.
      assert GitHistory.record_commits(project.id, "sha1", [commit("d", ["c"], 3)]) == :ok
      assert GitHistory.missing_shas(project.id, ["d"]) == []

      generations =
        Tuist.Repo.all(from(c in GitHistory.Commit, where: c.project_id == ^project.id, select: {c.sha, c.generation}))

      assert Map.new(generations) == %{"a" => 1, "b" => 2, "c" => 3, "d" => 4, "e" => 3}
    end

    test "a parent outside the window still gets an edge and counts as generation 0", %{project: project} do
      GitHistory.record_commits(project.id, "sha1", [commit("x", ["outside"], 0)])

      assert [{"x", 0}] = GitHistory.ancestors(project.id, "x")
      assert GitHistory.missing_shas(project.id, ["outside"]) == ["outside"]
    end
  end

  describe "ancestry" do
    test "walks parents with the shortest depth per commit", %{project: project} do
      seed(project)
      assert GitHistory.ancestors(project.id, "d") == [{"d", 0}, {"c", 1}, {"b", 2}, {"a", 3}]
      assert GitHistory.ancestors(project.id, "d", max_depth: 1) == [{"d", 0}, {"c", 1}]
    end

    test "finds the nearest candidate ancestor, the commit itself included", %{project: project} do
      seed(project)
      assert GitHistory.nearest_ancestor(project.id, "d", ["a", "b"]) == {"b", 2}
      assert GitHistory.nearest_ancestor(project.id, "d", ["d"]) == {"d", 0}
      assert GitHistory.nearest_ancestor(project.id, "d", ["e"]) == nil
      assert GitHistory.nearest_ancestor(project.id, "d", []) == nil
      assert GitHistory.ancestor?(project.id, "a", "e")
      refute GitHistory.ancestor?(project.id, "c", "e")
    end

    test "never takes a candidate from another project", %{project: project} do
      other = ProjectsFixtures.project_fixture()
      seed(project)
      GitHistory.record_commits(other.id, "sha1", [commit("d", [], 0)])

      assert GitHistory.nearest_ancestor(other.id, "d", ["c"]) == nil
    end

    test "computes a merge base from the graph", %{project: project} do
      seed(project)
      assert GitHistory.merge_base(project.id, "d", "e") == "b"
      assert GitHistory.merge_base(project.id, "d", "c") == "c"
      assert GitHistory.merge_base(project.id, "d", "unknown") == nil
    end
  end

  describe "branch heads" do
    test "keep the newest sha per branch", %{project: project} do
      GitHistory.record_branch_head(project.id, "main", "c")
      GitHistory.record_branch_head(project.id, "main", "d")
      GitHistory.record_branch_head(project.id, "", "d")

      assert GitHistory.branch_head(project.id, "main") == "d"
      assert GitHistory.branch_head(project.id, "") == nil
    end
  end

  describe "settings/1 and prune/1" do
    test "layers project overrides over the defaults", %{project: project} do
      assert %{window_days: 365, window_commits: 5_000, provider_fallback: true, upload_batch_size: 500} =
               GitHistory.settings(project)

      {:ok, project} =
        Projects.update_project(project, %{git_history_window_days: 30, git_history_provider_fallback: false})

      assert %{window_days: 30, provider_fallback: false, window_commits: 5_000} = GitHistory.settings(project)
    end

    test "drops commits older than the window and their parent edges", %{project: project} do
      {:ok, project} = Projects.update_project(project, %{git_history_window_days: 1})
      old = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)

      GitHistory.record_commits(project.id, "sha1", [
        %{sha: "old", parents: [], committed_at: old},
        %{sha: "new", parents: ["old"], committed_at: DateTime.utc_now()}
      ])

      assert {:ok, 1} = GitHistory.prune(project)
      assert GitHistory.missing_shas(project.id, ["old", "new"]) == ["old"]
      # The edge from the kept commit to the dropped one marks the window's end.
      assert GitHistory.ancestors(project.id, "new") == [{"new", 0}]
    end
  end
end
