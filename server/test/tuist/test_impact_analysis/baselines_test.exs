defmodule Tuist.TestImpactAnalysis.BaselinesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.GitHistory
  alias Tuist.TestImpactAnalysis.Baselines
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

  # Coverage that doesn't make the commit a baseline: only a partial run.
  defp measured(project, repository_id, sha),
    do: CoverageFixtures.commit_coverage(project, repository_id, sha, runs: [[partial: true]])

  defp outcome({:ok, %{sha: sha}}), do: {:ok, sha}
  defp outcome(error), do: error

  defp scope(commit_sha, attrs \\ %{}), do: Map.merge(%{commit_sha: commit_sha, platform: "ios", scheme: "App"}, attrs)

  describe "resolve/3" do
    test "is the nearest full run, counting only commits with coverage", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 30, nil))
      [run_id] = CoverageFixtures.commit_coverage(project, repository_id, "c2")
      CoverageFixtures.commit_coverage(project, repository_id, "c1")
      measured(project, repository_id, "c10")
      measured(project, repository_id, "c20")

      assert {:ok, baseline} = Baselines.resolve(project, scope("c30"))
      assert baseline.sha == "c2"
      assert baseline.repository_id == repository_id
      assert baseline.run_ids == [run_id]
      assert baseline.distance == 3
      assert Enum.sort(baseline.window_shas) == Enum.sort(for i <- 2..30, do: "c#{i}")
    end

    test "is the checked-out commit itself when it has a full run", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 3, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c3")

      assert {:ok, %{sha: "c3", distance: 0, window_shas: ["c3"]}} = Baselines.resolve(project, scope("c3"))
    end

    test "accepts a baseline 20 commits with coverage back", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 21, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c1")
      for i <- 2..20, do: measured(project, repository_id, "c#{i}")

      assert {:ok, %{sha: "c1", distance: 20}} = Baselines.resolve(project, scope("c21"))
    end

    test "answers baseline_too_old past 20 commits with coverage", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 22, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c1")
      for i <- 2..21, do: measured(project, repository_id, "c#{i}")

      assert Baselines.resolve(project, scope("c22")) == {:error, :baseline_too_old}
    end

    test "walks past the first depths to a baseline beyond many commits without coverage", %{
      account: account,
      project: project
    } do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 300, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c1")

      assert {:ok, %{sha: "c1", distance: 1}} = Baselines.resolve(project, scope("c300"))
    end

    test "walks from both parents of a merge checkout the history doesn't have", %{account: account, project: project} do
      # main: m1 → m2 → m3; the pull request: m1 → p1 → p2.
      repository_id = CoverageFixtures.seed_history(account, chain("m", 3, nil) ++ chain("p", 2, "m1", 10))
      CoverageFixtures.commit_coverage(project, repository_id, "m3")

      assert {:ok, baseline} = Baselines.resolve(project, scope("merge", %{parent_shas: ["p2", "m3"]}))
      assert baseline.sha == "m3"
      assert baseline.distance == 1
      refute "merge" in baseline.window_shas
      assert Baselines.resolve(project, scope("p2")) == {:error, :no_baseline}
    end

    test "answers history_unknown until the client uploads the checkout's history", %{
      account: account,
      project: project
    } do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 2, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c1")

      assert Baselines.resolve(project, scope("f2")) == {:error, :history_unknown}
      assert Baselines.resolve(project, scope("f2", %{parent_shas: ["f1"]})) == {:error, :history_unknown}

      # The client deepens its checkout and uploads the graph it now has.
      GitHistory.record_commits(repository_id, "sha1", chain("f", 2, "c2", 10))

      assert {:ok, %{sha: "c1", distance: 1}} = Baselines.resolve(project, scope("f2"))
    end

    test "answers no_baseline when the project has no coverage to walk from", %{account: account, project: project} do
      CoverageFixtures.seed_history(account, chain("c", 2, nil))

      assert Baselines.resolve(project, scope("unknown")) == {:error, :no_baseline}
    end

    test "only picks a run on the requested platform", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 3, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c2", runs: [[platform: "macos"]])
      CoverageFixtures.commit_coverage(project, repository_id, "c1")

      assert {:ok, %{sha: "c1"}} = Baselines.resolve(project, scope("c3"))
      assert {:ok, %{sha: "c2"}} = Baselines.resolve(project, scope("c3", %{platform: "macos"}))
      assert Baselines.resolve(project, scope("c3", %{platform: "tvos"})) == {:error, :no_baseline}
    end

    test "keeps to the requested scheme's full runs", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 5, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c4", runs: [[scheme: "Other"]])
      CoverageFixtures.commit_coverage(project, repository_id, "c3", runs: [[partial: true]], partial_schemes: ["App"])
      CoverageFixtures.commit_coverage(project, repository_id, "c2", runs: [[partial: true], [scheme: "Other"]])
      [run_id, _other] = CoverageFixtures.commit_coverage(project, repository_id, "c1", runs: [[], [scheme: "Other"]])

      assert {:ok, %{sha: "c1", run_ids: [^run_id], distance: 4}} = Baselines.resolve(project, scope("c5"))
      assert {:ok, %{sha: "c4"}} = Baselines.resolve(project, scope("c5", %{scheme: "Other"}))
      assert {:ok, %{sha: "c4"}} = Baselines.resolve(project, scope("c5", %{scheme: nil}))
    end

    test "answers no_baseline_evidence when the run in reach uploaded no test-scoped evidence", %{
      account: account,
      project: project
    } do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 2, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c1", runs: [[evidence: false]])

      assert Baselines.resolve(project, scope("c2")) == {:error, :no_baseline_evidence}
    end

    test "passes over a nearer run without evidence to one with it", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 3, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c2", runs: [[evidence: false]])
      CoverageFixtures.commit_coverage(project, repository_id, "c1")

      assert {:ok, %{sha: "c1", distance: 2}} = Baselines.resolve(project, scope("c3"))
    end

    test "answers no_baseline without any full run", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 3, nil))
      measured(project, repository_id, "c1")

      assert Baselines.resolve(project, scope("c3")) == {:error, :no_baseline}
    end

    test "with baseline_sha, resolves only that commit", %{account: account, project: project} do
      repository_id = CoverageFixtures.seed_history(account, chain("c", 4, nil))
      CoverageFixtures.commit_coverage(project, repository_id, "c3")
      CoverageFixtures.commit_coverage(project, repository_id, "c1")

      assert {:ok, %{sha: "c1", distance: 2, window_shas: window}} =
               Baselines.resolve(project, scope("c4"), baseline_sha: "c1")

      assert Enum.sort(window) == ["c1", "c2", "c3", "c4"]
      assert Baselines.resolve(project, scope("c4"), baseline_sha: "c9") == {:error, :no_baseline}
    end

    test "ignores another project's coverage", %{account: account, project: project} do
      other = ProjectsFixtures.project_fixture(account_id: account.id)
      repository_id = CoverageFixtures.seed_history(account, chain("c", 2, nil))
      CoverageFixtures.commit_coverage(other, repository_id, "c1")

      assert Baselines.resolve(project, scope("c2")) == {:error, :no_baseline}
    end
  end

  describe "resolve/3 on the test bed's window scenarios" do
    # cli/Tests/Fixtures/CoverageTestSelection: feature/evidence-window commits
    # revisions 1 to 21 on top of the baseline, and scenarios.sh checks out
    # revision 20 for window_at_cap and 21 for the others.
    @golden_path Path.expand("../../../../cli/Tests/Fixtures/CoverageTestSelection/golden.json", __DIR__)
    @external_resource @golden_path
    @checkouts %{"checkout/window-at-cap" => 20, "checkout/window-over-cap" => 21, "checkout/window-unmeasured" => 21}

    for scenario <- @golden_path |> File.read!() |> JSON.decode!() |> Map.fetch!("scenarios"),
        Map.has_key?(@checkouts, scenario["checkout"]["ref"]) do
      @scenario scenario
      @expected (case scenario do
                   %{"outcome" => "selected", "baseline" => baseline} -> {:ok, baseline}
                   %{"outcome" => "fallback", "reason" => reason} -> {:error, String.to_atom(reason)}
                 end)

      test scenario["name"], %{account: account, project: project} do
        commits = [CoverageFixtures.commit("baseline", [], 0) | chain("run/evidence-window/", 21, "baseline")]
        repository_id = CoverageFixtures.seed_history(account, commits)
        [_baseline | runs] = @scenario["runs"]
        CoverageFixtures.commit_coverage(project, repository_id, "baseline")

        # Each run after the baseline is a selection on the branch: partial.
        for %{"ref" => "run/evidence-window/" <> revision} <- runs,
            do: measured(project, repository_id, "run/evidence-window/#{String.to_integer(revision)}")

        checkout = "run/evidence-window/#{@checkouts[@scenario["checkout"]["ref"]]}"

        assert outcome(Baselines.resolve(project, scope(checkout))) == @expected
      end
    end
  end
end
