defmodule Tuist.Tests.Coverage.ComparisonTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.GitHistory
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.Coverage.Comparison
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")
    %{account: account, project: project}
  end

  # main: a → b → c; a pull request commit p branches off b; e is a stray
  # commit whose parent the graph does not know.
  defp seed_history(project) do
    GitHistory.record_commits(project.id, "sha1", [
      commit("a", [], 0),
      commit("b", ["a"], 1),
      commit("c", ["b"], 2),
      commit("p", ["b"], 3),
      commit("e", ["x"], 4)
    ])
  end

  defp commit(sha, parents, minutes) do
    %{sha: sha, parents: parents, committed_at: DateTime.add(~U[2026-09-01 00:00:00Z], minutes * 60, :second)}
  end

  defp file(path, blob, targets, counts) do
    %{
      path: path,
      git_blob_id: blob,
      targets: targets,
      covered_lines: Enum.count(counts, &(&1 > 0)),
      executable_lines: length(counts),
      line_numbers: Enum.to_list(1..length(counts)),
      execution_counts: counts,
      functions: []
    }
  end

  defp run(project, account, attrs) do
    {:ok, run} =
      Tests.create_test(
        Map.merge(
          %{
            id: UUIDv7.generate(),
            project_id: project.id,
            account_id: account.id,
            duration: 1000,
            status: "success",
            scheme: "App",
            git_branch: "main",
            ran_at: NaiveDateTime.utc_now(),
            is_ci: true,
            test_modules: []
          },
          attrs
        )
      )

    {:ok, run} = Tests.get_test(run.id)
    run
  end

  defp main_run(project, account, sha, files, attrs \\ %{}) do
    run(
      project,
      account,
      Map.merge(
        %{
          git_commit_sha: sha,
          ran_at: NaiveDateTime.add(~N[2026-09-01 00:00:00], hd(String.to_charlist(sha)), :minute),
          xcode_coverage: %{partial: false, files: files}
        },
        attrs
      )
    )
  end

  defp pr_run(project, account, files, attrs \\ %{}) do
    run(
      project,
      account,
      Map.merge(
        %{
          git_branch: "feature",
          git_commit_sha: "p",
          base_branch: "main",
          merge_base_sha: "b",
          is_pull_request: true,
          pull_request_number: 7,
          history_source: "client",
          xcode_coverage: %{partial: Map.get(attrs, :partial, false), files: files}
        },
        Map.delete(attrs, :partial)
      )
    )
  end

  # The base branch's state: Add fully covered, Untested not at all.
  defp base_files do
    [
      file("Sources/Add.swift", "add1", ["Calculator"], [1, 1, 1, 1]),
      file("Sources/Untested.swift", "untested1", ["Calculator"], [0, 0]),
      file("Sources/Format.swift", "format1", ["Formatter"], [1, 1])
    ]
  end

  describe "baseline/2" do
    test "is the full run at the merge base when there is one", %{project: project, account: account} do
      seed_history(project)
      main_run(project, account, "a", base_files())
      at_base = main_run(project, account, "b", base_files())
      pr = pr_run(project, account, base_files())

      assert {:ok, baseline} = Comparison.baseline(project, pr)
      assert {baseline.test_run_id, baseline.commit, baseline.depth, baseline.branch} == {at_base.id, "b", 0, "main"}
      assert {baseline.covered_lines, baseline.executable_lines} == {6, 8}
    end

    test "walks back to the nearest ancestor with a full run", %{project: project, account: account} do
      seed_history(project)
      at_a = main_run(project, account, "a", base_files())
      pr = pr_run(project, account, base_files())

      assert {:ok, %{test_run_id: run_id, commit: "a", depth: 1}} = Comparison.baseline(project, pr)
      assert run_id == at_a.id
    end

    test "prefers the newest full run of a commit and ignores partial and other schemes", %{
      project: project,
      account: account
    } do
      seed_history(project)
      _older = main_run(project, account, "b", base_files(), %{ran_at: ~N[2026-09-01 00:00:00]})
      newest = main_run(project, account, "b", base_files(), %{ran_at: ~N[2026-09-01 01:00:00]})
      _partial = main_run(project, account, "b", base_files(), %{xcode_coverage: %{partial: true, files: base_files()}})
      _other_scheme = main_run(project, account, "b", base_files(), %{scheme: "Other", ran_at: ~N[2026-09-02 00:00:00]})
      pr = pr_run(project, account, base_files())

      assert {:ok, %{test_run_id: run_id}} = Comparison.baseline(project, pr)
      assert run_id == newest.id
    end

    test "compares a run on the base branch with the commit before it, never with itself", %{
      project: project,
      account: account
    } do
      seed_history(project)
      at_a = main_run(project, account, "a", base_files())
      at_b = main_run(project, account, "b", base_files())

      assert {:ok, %{test_run_id: run_id, commit: "a", depth: 1}} = Comparison.baseline(project, at_b)
      assert run_id == at_a.id
      # The only other full run is on a descendant, which is no baseline.
      assert {:error, %{kind: :no_ancestor_run, commit: "a"}} = Comparison.baseline(project, at_a)
    end

    test "says why there is no baseline", %{project: project, account: account} do
      pr = pr_run(project, account, base_files())
      assert {:error, %{kind: :no_full_runs, base_branch: "main", scheme: "App"}} = Comparison.baseline(project, pr)

      # A full run exists, but the merge base is not in the graph.
      main_run(project, account, "a", base_files())
      assert {:error, %{kind: :no_history, commit: "b"}} = Comparison.baseline(project, pr)

      # The graph knows the merge base, but no full run is on an ancestor.
      seed_history(project)
      stray = pr_run(project, account, base_files(), %{merge_base_sha: "e", git_commit_sha: "e"})
      assert {:error, %{kind: :no_ancestor_run, commit: "e"}} = Comparison.baseline(project, stray)

      # A pull request whose merge base the client could not find, and whose
      # base branch head is unknown too.
      orphan =
        pr_run(project, account, base_files(), %{merge_base_sha: "", history_fallback_reason: "shallow clone"})

      assert {:error, %{kind: :no_merge_base, detail: "shallow clone"}} = Comparison.baseline(project, orphan)

      # With the base branch head recorded, the merge base comes from the graph.
      GitHistory.record_branch_head(project.id, "main", "c")
      assert {:ok, %{commit: "a", depth: 1}} = Comparison.baseline(project, orphan)
    end
  end

  describe "compare/3 on a full run" do
    setup %{project: project, account: account} do
      seed_history(project)
      main_run(project, account, "b", base_files())
      :ok
    end

    test "gives the total, target and file deltas, patch coverage and gaps", %{project: project, account: account} do
      pr =
        pr_run(
          project,
          account,
          [
            # One line lost its coverage, and two new lines were added, one covered.
            file("Sources/Add.swift", "add2", ["Calculator"], [1, 1, 0, 1, 1, 0]),
            file("Sources/Untested.swift", "untested1", ["Calculator"], [0, 0]),
            file("Sources/Format.swift", "format1", ["Formatter"], [1, 1]),
            file("Sources/New.swift", "new1", ["Calculator"], [0, 0, 0])
          ],
          %{
            changed_files: [
              %{path: "Sources/Add.swift", status: "modified", git_blob_id: "add2", hunks: [%{start: 5, end: 6}]},
              %{path: "Sources/New.swift", status: "added", git_blob_id: "new1", hunks: [%{start: 1, end: 3}]},
              %{path: "README.md", status: "modified", git_blob_id: "readme2", hunks: [%{start: 1, end: 1}]},
              %{path: "Sources/Gone.swift", status: "deleted"}
            ]
          }
        )

      comparison = Comparison.compare(project, pr)

      assert comparison.run.partial == false
      assert {comparison.run.covered_lines, comparison.run.executable_lines, comparison.run.coverage} == {6, 13, 46.2}
      assert comparison.baseline.commit == "b"
      assert comparison.baseline.coverage == 75.0
      assert comparison.baseline_reason == nil
      assert comparison.total_delta == -28.8

      assert [
               %{name: "Calculator", coverage: 36.4, baseline_coverage: 66.7, delta: -30.3},
               %{name: "Formatter", coverage: 100.0, baseline_coverage: 100.0, delta: +0.0}
             ] = comparison.targets

      assert [
               %{path: "Sources/Add.swift", coverage: 66.7, baseline_coverage: 100.0, delta: -33.3},
               %{path: "Sources/New.swift", coverage: +0.0, baseline_coverage: nil, delta: nil}
             ] = comparison.files

      assert comparison.patch.status == :available

      assert {comparison.patch.covered_lines, comparison.patch.executable_lines, comparison.patch.coverage} ==
               {1, 5, 20.0}

      assert [
               %{path: "Sources/New.swift", covered_lines: 0, executable_lines: 3, uncovered_ranges: [{1, 3}]},
               %{path: "Sources/Add.swift", covered_lines: 1, executable_lines: 2, uncovered_ranges: [{6, 6}]}
             ] = comparison.patch.files

      assert comparison.patch.skipped == [%{path: "README.md", reason: :not_instrumented}]
      assert comparison.gaps == [%{path: "Sources/New.swift", executable_lines: 3}]
    end

    test "leaves out of the patch the files it cannot map to the run's lines", %{project: project, account: account} do
      pr =
        pr_run(
          project,
          account,
          [
            file("Sources/Add.swift", "add-from-another-checkout", ["Calculator"], [1, 1, 1, 1]),
            %{
              path: "Sources/NoLines.swift",
              git_blob_id: "nolines1",
              targets: ["Calculator"],
              covered_lines: 1,
              executable_lines: 2,
              line_numbers: [],
              execution_counts: [],
              functions: []
            }
          ],
          %{
            changed_files: [
              %{path: "Sources/Add.swift", status: "modified", git_blob_id: "add2", hunks: [%{start: 1, end: 2}]},
              %{path: "Sources/NoLines.swift", status: "modified", git_blob_id: "nolines1", hunks: [%{start: 1, end: 1}]},
              %{path: "Sources/Big.swift", status: "modified", git_blob_id: "big1", hunks: [], truncated: true}
            ]
          }
        )

      %{patch: patch, gaps: gaps} = Comparison.compare(project, pr)

      assert patch.status == :available
      assert patch.executable_lines == 0
      assert patch.files == []
      assert gaps == []

      assert patch.skipped == [
               %{path: "Sources/Add.swift", reason: :stale},
               %{path: "Sources/Big.swift", reason: :truncated},
               %{path: "Sources/NoLines.swift", reason: :no_line_data}
             ]
    end

    test "reports the missing history instead of an empty patch", %{project: project, account: account} do
      pr =
        pr_run(project, account, base_files(), %{history_source: "none", history_fallback_reason: "not a git checkout"})

      comparison = Comparison.compare(project, pr)
      assert comparison.patch == %{status: :unavailable, reason: :no_history, detail: "not a git checkout"}
      assert comparison.gaps == []
    end

    test "keeps the reason when there is no baseline", %{project: project, account: account} do
      pr = pr_run(project, account, base_files(), %{merge_base_sha: "zzz", changed_files: []})

      comparison = Comparison.compare(project, pr)
      assert comparison.baseline == nil
      assert comparison.baseline_reason.kind == :no_history
      assert comparison.total_delta == nil
      assert comparison.files == []
      assert Enum.map(comparison.targets, &{&1.name, &1.delta}) == [{"Calculator", nil}, {"Formatter", nil}]
      assert comparison.patch.status == :available
    end

    test "is nil for a run without coverage", %{project: project, account: account} do
      run = run(project, account, %{git_commit_sha: "c"})
      assert Comparison.compare(project, run) == nil
    end
  end

  describe "compare/3 on a partial run" do
    setup %{project: project, account: account} do
      seed_history(project)
      main_run(project, account, "b", base_files())

      pr =
        pr_run(
          project,
          account,
          [
            file("Sources/Add.swift", "add1", ["Calculator"], [1, 0, 0, 0]),
            file("Sources/Format.swift", "format1", ["Formatter"], [0, 0])
          ],
          %{
            partial: true,
            changed_files: [
              %{path: "Sources/Add.swift", status: "modified", git_blob_id: "add1", hunks: [%{start: 1, end: 2}]}
            ]
          }
        )

      %{pr: pr}
    end

    test "has no total delta and compares only the files some test executed", %{project: project, pr: pr} do
      comparison = Comparison.compare(project, pr)

      assert comparison.run.partial
      assert comparison.baseline.commit == "b"
      assert comparison.total_delta == nil

      assert [
               %{name: "Calculator", delta: -41.7},
               %{name: "Formatter", coverage: +0.0, baseline_coverage: 100.0, delta: nil}
             ] = comparison.targets

      assert [%{path: "Sources/Add.swift", delta: -75.0}] = comparison.files
      assert comparison.patch == %{status: :unavailable, reason: :partial_run}
      assert comparison.gaps == []
    end

    test "computes the patch when the project allows it on partial runs", %{project: project, pr: pr} do
      {:ok, project} = Projects.update_project(project, %{coverage_patch_partial_runs: true})

      %{patch: patch} = Comparison.compare(project, pr)
      assert {patch.status, patch.covered_lines, patch.executable_lines} == {:available, 1, 2}
    end
  end
end
