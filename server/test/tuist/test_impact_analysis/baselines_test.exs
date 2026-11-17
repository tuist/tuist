defmodule Tuist.TestImpactAnalysis.BaselinesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.GitHistory
  alias Tuist.Repo
  alias Tuist.TestImpactAnalysis.Baselines
  alias Tuist.TestImpactAnalysis.Snapshot
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{account: account, project: project}
  end

  # A linear history `prefix1 → … → prefixN` on top of `parent`, oldest first.
  defp chain(prefix, n, parent, start_minute \\ 0) do
    {commits, _} =
      Enum.map_reduce(1..n, parent, fn i, parent ->
        sha = "#{prefix}#{i}"
        {CoverageFixtures.commit(sha, List.wrap(parent), start_minute + i), sha}
      end)

    commits
  end

  # A snapshot at `sha`, a live checkpoint of scheme App on iOS by default.
  defp snapshot(project, repository_id, sha, attrs \\ []) do
    now = DateTime.utc_now()

    Repo.insert!(
      struct!(
        Snapshot,
        Keyword.merge(
          [
            id: UUIDv7.generate(),
            project_id: project.id,
            repository_id: repository_id,
            commit_sha: sha,
            kind: :checkpoint,
            scheme: "App",
            platform: "ios",
            test_run_ids: [UUIDv7.generate()],
            ran_at: now,
            expires_at: DateTime.add(now, 31, :day)
          ],
          attrs
        )
      )
    )
  end

  defp scope(commit_sha, attrs \\ %{}), do: Map.merge(%{commit_sha: commit_sha, platform: "ios", scheme: "App"}, attrs)

  describe "resolve/3" do
    test "is the nearest checkpoint, with the runs it holds", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 30, nil))
      checkpoint = snapshot(project, repository_id, "c2")
      snapshot(project, repository_id, "c1")

      assert {:ok, baseline} = Baselines.resolve(project, scope("c30"))
      assert baseline.sha == "c2"
      assert baseline.repository_id == repository_id
      assert baseline.checkpoint.id == checkpoint.id
      assert baseline.run_ids == checkpoint.test_run_ids
      assert baseline.distance == 28
    end

    test "is the checked-out commit itself when it has a checkpoint", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 3, nil))
      snapshot(project, repository_id, "c3")

      assert {:ok, %{sha: "c3", distance: 0}} = Baselines.resolve(project, scope("c3"))
    end

    # Commits measured without a checkpoint used to count toward a cap of 20.
    test "walks past the first depths, past overlays and expired checkpoints", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 300, nil))
      snapshot(project, repository_id, "c1")
      snapshot(project, repository_id, "c200", kind: :overlay)
      snapshot(project, repository_id, "c250", expires_at: DateTime.add(DateTime.utc_now(), -1, :minute))

      assert {:ok, %{sha: "c1", distance: 299}} = Baselines.resolve(project, scope("c300"))
    end

    test "walks from both parents of a merge checkout the history doesn't have", %{account: account, project: project} do
      # main: m1 → m2 → m3; the pull request: m1 → p1 → p2.
      repository_id = CoverageFixtures.seed_history(account, chain("m", 3, nil) ++ chain("p", 2, "m1", 10))
      snapshot(project, repository_id, "m3")

      assert {:ok, %{sha: "m3", distance: 1}} = Baselines.resolve(project, scope("merge", %{parent_shas: ["p2", "m3"]}))
      assert Baselines.resolve(project, scope("p2")) == {:error, :no_baseline}
    end

    test "answers history_unknown until the client uploads the checkout's history", %{
      account: account,
      project: project
    } do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 2, nil))
      snapshot(project, repository_id, "c1")

      assert Baselines.resolve(project, scope("f2")) == {:error, :history_unknown}
      assert Baselines.resolve(project, scope("f2", %{parent_shas: ["f1"]})) == {:error, :history_unknown}

      # The client deepens its checkout and uploads the graph it now has.
      GitHistory.record_commits(repository_id, "sha1", chain("f", 2, "c2", 10))

      assert {:ok, %{sha: "c1", distance: 3}} = Baselines.resolve(project, scope("f2"))
    end

    test "walks from the known ancestors sent", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 5, nil))
      snapshot(project, repository_id, "c1")
      ancestors = %{parent_shas: ["x2"], ancestor_shas: ["x2", "x1", "c5", "c4", "c3"]}

      assert {:ok, %{sha: "c1", distance: 7}} = Baselines.resolve(project, scope("x3", ancestors))

      assert Baselines.resolve(project, scope("x3", %{parent_shas: ["x2"], ancestor_shas: ["x2", "x1"]})) ==
               {:error, :history_unknown}
    end

    test "reads only the first 200 ancestors sent", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 2, nil))
      snapshot(project, repository_id, "c1")
      unknown = for i <- 1..199, do: "u#{i}"

      assert {:ok, %{sha: "c1"}} = Baselines.resolve(project, scope("x", %{ancestor_shas: unknown ++ ["c2"]}))

      assert Baselines.resolve(project, scope("x", %{ancestor_shas: unknown ++ ["u200", "c2"]})) ==
               {:error, :history_unknown}
    end

    test "answers no_baseline when the project has no checkpoint to walk from", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 2, nil))
      other = ProjectsFixtures.project_fixture(account_id: account.id)
      snapshot(other, repository_id, "c1")

      assert Baselines.resolve(project, scope("c2")) == {:error, :no_baseline}
    end

    test "keeps to the requested platform and scheme", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 5, nil))
      snapshot(project, repository_id, "c4", scheme: "Other")
      snapshot(project, repository_id, "c3", platform: "macos")
      snapshot(project, repository_id, "c1")

      assert {:ok, %{sha: "c1"}} = Baselines.resolve(project, scope("c5"))
      assert {:ok, %{sha: "c4"}} = Baselines.resolve(project, scope("c5", %{scheme: "Other"}))
      assert {:ok, %{sha: "c4"}} = Baselines.resolve(project, scope("c5", %{scheme: nil}))
      assert {:ok, %{sha: "c3"}} = Baselines.resolve(project, scope("c5", %{platform: "macos"}))
      assert Baselines.resolve(project, scope("c5", %{platform: "tvos"})) == {:error, :no_baseline}
    end

    test "takes the newest checkpoint at a commit", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 2, nil))
      now = DateTime.utc_now()
      snapshot(project, repository_id, "c1", ran_at: DateTime.add(now, -1, :hour))
      newest = snapshot(project, repository_id, "c1", ran_at: now)

      assert {:ok, %{checkpoint: %{id: id}}} = Baselines.resolve(project, scope("c2"))
      assert id == newest.id
    end

    test "with baseline_sha, resolves only that commit", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 4, nil))
      snapshot(project, repository_id, "c3")
      snapshot(project, repository_id, "c1")

      assert {:ok, %{sha: "c1", distance: 3}} = Baselines.resolve(project, scope("c4"), baseline_sha: "c1")
      assert Baselines.resolve(project, scope("c4"), baseline_sha: "c2") == {:error, :no_baseline}
      assert Baselines.resolve(project, scope("c4"), baseline_sha: "c9") == {:error, :no_baseline}
    end
  end
end
