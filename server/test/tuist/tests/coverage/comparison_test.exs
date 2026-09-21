defmodule Tuist.Tests.Coverage.ComparisonTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Projects
  alias Tuist.Tests.Coverage.Comparison
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id, default_branch: "main")
    %{account: account, project: project}
  end

  # main: a → b → c; a pull request commit p branches off b; e is a stray
  # commit whose parent the graph does not know.
  defp seed_history(account) do
    CoverageFixtures.seed_history(account, [
      CoverageFixtures.commit("a", [], 0),
      CoverageFixtures.commit("b", ["a"], 1),
      CoverageFixtures.commit("c", ["b"], 2),
      CoverageFixtures.commit("p", ["b"], 3),
      CoverageFixtures.commit("e", ["x"], 4)
    ])
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

  defp main_run(project, account, sha, files, attrs \\ %{}) do
    CoverageFixtures.run_with_coverage(
      project,
      account,
      files,
      Map.merge(
        %{git_commit_sha: sha, ran_at: NaiveDateTime.add(~N[2026-09-01 00:00:00], hd(String.to_charlist(sha)), :minute)},
        attrs
      )
    )
  end

  defp pr_run(project, account, files, attrs \\ %{}) do
    CoverageFixtures.run_with_coverage(
      project,
      account,
      files,
      Map.merge(
        %{
          git_branch: "feature",
          git_commit_sha: "p",
          base_branch: "main",
          merge_base_sha: "b",
          is_pull_request: true,
          pull_request_number: 7,
          history_source: "client"
        },
        attrs
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
    test "is the measured commit at the merge base when there is one", %{project: project, account: account} do
      seed_history(account)
      main_run(project, account, "a", base_files())
      main_run(project, account, "b", base_files())
      pr = pr_run(project, account, base_files())

      assert {:ok, baseline} = Comparison.baseline(project, pr)
      assert {baseline.commit, baseline.depth, baseline.branch, baseline.schemes} == {"b", 0, "main", ["App"]}
      assert {baseline.covered_lines, baseline.executable_lines} == {6, 8}
    end

    test "walks back along first parents to the nearest measured ancestor", %{project: project, account: account} do
      seed_history(account)
      main_run(project, account, "a", base_files())
      pr = pr_run(project, account, base_files())

      assert {:ok, %{commit: "a", depth: 1}} = Comparison.baseline(project, pr)
    end

    test "takes a commit as one measurement whatever measured it, and refuses one measured unlike the head", %{
      project: project,
      account: account
    } do
      seed_history(account)
      main_run(project, account, "b", base_files(), %{ran_at: ~N[2026-09-01 00:00:00]})
      main_run(project, account, "b", base_files(), %{ran_at: ~N[2026-09-01 01:00:00], partial: true})
      main_run(project, account, "b", base_files(), %{scheme: "Other", ran_at: ~N[2026-09-02 00:00:00]})
      pr = pr_run(project, account, base_files())

      assert {:error,
              %{kind: :measured_set_mismatch, commit: "b", schemes: ["App"], baseline_schemes: ["App", "Other"]} = reason} =
               Comparison.baseline(project, pr)

      assert Comparison.reason_text(reason) == "commit `b` measured `App`, `Other` where this commit measured `App`"

      pr_run(project, account, base_files(), %{scheme: "Other"})
      assert {:ok, %{commit: "b", schemes: ["App", "Other"], partial_schemes: []}} = Comparison.baseline(project, pr)
    end

    test "a run from a dirty checkout is compared as itself, not as its commit", %{
      project: project,
      account: account
    } do
      seed_history(account)
      main_run(project, account, "a", base_files())
      dirty = main_run(project, account, "b", base_files(), %{git_dirty: true})

      comparison = Comparison.compare(project, dirty)

      assert comparison.baseline == nil
      assert comparison.baseline_reason.kind == :dirty_checkout
      assert comparison.total_delta == nil
      assert comparison.patch.status == :unavailable
      assert comparison.patch.reason == :dirty_checkout

      assert Comparison.reason_text(comparison.baseline_reason) ==
               "the checkout had uncommitted changes, so this run measured code that is not the commit's"
    end

    test "compares a commit on the base branch with its first parent, never with itself", %{
      project: project,
      account: account
    } do
      seed_history(account)
      at_a = main_run(project, account, "a", base_files())
      at_b = main_run(project, account, "b", base_files())

      assert {:ok, %{commit: "a", depth: 0}} = Comparison.baseline(project, at_b)
      # The first commit has no parent in the graph, and a descendant is no baseline.
      assert {:error, %{kind: :no_history, commit: "a"}} = Comparison.baseline(project, at_a)
    end

    test "says why there is no baseline", %{project: project, account: account} do
      pr = pr_run(project, account, base_files())
      assert {:error, %{kind: :no_measured_commits, base_branch: "main"}} = Comparison.baseline(project, pr)

      # A measured commit exists, but the merge base is not in the graph.
      main_run(project, account, "a", base_files())
      assert {:error, %{kind: :no_history, commit: "b"}} = Comparison.baseline(project, pr)

      # The graph knows the merge base, but no measured commit is on its ancestry.
      seed_history(account)
      stray = pr_run(project, account, base_files(), %{merge_base_sha: "e", git_commit_sha: "e"})
      assert {:error, %{kind: :no_ancestor_commit, commit: "e"}} = Comparison.baseline(project, stray)

      # A pull request whose merge base the client could not find, and whose
      # base branch head is unknown too.
      orphan =
        pr_run(project, account, base_files(), %{merge_base_sha: "", history_fallback_reason: "shallow clone"})

      assert {:error, %{kind: :no_merge_base, detail: "shallow clone"}} = Comparison.baseline(project, orphan)

      # With the base branch head recorded, the merge base comes from the graph.
      Tuist.GitHistory.record_branch_head(CoverageFixtures.repository_id(account), "main", "c")
      assert {:ok, %{commit: "a", depth: 1}} = Comparison.baseline(project, orphan)
    end

    test "has no baseline for a run without a repository", %{project: project, account: account} do
      run = pr_run(project, account, base_files(), %{git_remote_url_origin: nil})
      assert {:error, %{kind: :no_history, commit: "p"}} = Comparison.baseline(project, run)
    end
  end

  describe "compare/3 on a fully measured commit" do
    setup %{project: project, account: account} do
      seed_history(account)
      main_run(project, account, "b", base_files())
      :ok
    end

    test "gives the total, scheme, target and file deltas, patch coverage and gaps", %{
      project: project,
      account: account
    } do
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

      assert {comparison.commit.sha, comparison.commit.partial, comparison.commit.schemes} == {"p", false, ["App"]}

      assert {comparison.commit.covered_lines, comparison.commit.executable_lines, comparison.commit.coverage} ==
               {6, 13, 46.2}

      assert comparison.baseline.commit == "b"
      assert comparison.baseline.coverage == 75.0
      assert comparison.baseline_reason == nil
      assert comparison.total_delta == -28.8

      assert [%{scheme: "App", coverage: 46.2, baseline_coverage: 75.0, delta: -28.8, partial: false}] =
               comparison.schemes

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

    test "unions the runs that measured the commit: a line any of them covered is covered", %{
      project: project,
      account: account
    } do
      pr_run(project, account, [file("Sources/Add.swift", "add1", ["Calculator"], [1, 1, 0, 0])], %{
        ran_at: ~N[2026-09-02 00:00:00]
      })

      pr =
        pr_run(project, account, [file("Sources/Add.swift", "add1", ["Calculator"], [0, 0, 1, 0])], %{
          scheme: "Other",
          ran_at: ~N[2026-09-02 01:00:00]
        })

      comparison = Comparison.compare(project, pr)

      assert {comparison.commit.covered_lines, comparison.commit.executable_lines} == {3, 4}
      assert comparison.commit.schemes == ["App", "Other"]
      # The baseline only measured App, so the whole is not compared; each scheme's own total is.
      assert comparison.baseline == nil
      assert comparison.baseline_reason.kind == :measured_set_mismatch
      assert comparison.total_delta == nil

      # `App` ran on both, so it compares; `Other` is the scheme the ancestor
      # lacks, which is why the totals do not compare at all.
      assert Enum.map(comparison.schemes, &{&1.scheme, &1.coverage, &1.baseline_coverage, &1.delta}) == [
               {"App", 50.0, 75.0, -25.0},
               {"Other", 25.0, nil, nil}
             ]
    end

    test "leaves the excluded paths out of both sides and lists the changed ones as excluded", %{
      project: project,
      account: account
    } do
      pr =
        pr_run(
          project,
          account,
          base_files() ++ [file("Sources/API/Client.swift", "client1", ["Calculator"], [0, 0, 0, 0])],
          %{
            changed_files: [
              %{path: "Sources/API/Client.swift", status: "added", git_blob_id: "client1", hunks: [%{start: 1, end: 4}]}
            ]
          }
        )

      # Excluding a file the baseline measured moves neither side's total.
      {:ok, project} =
        Projects.update_project(project, %{coverage_excluded_path_globs: ["Sources/API/**", "Sources/Format.swift"]})

      comparison = Comparison.compare(project, pr)

      assert {comparison.commit.covered_lines, comparison.commit.executable_lines} == {4, 6}
      assert {comparison.baseline.covered_lines, comparison.baseline.executable_lines} == {4, 6}
      assert comparison.total_delta == +0.0
      assert Enum.map(comparison.targets, & &1.name) == ["Calculator"]
      assert comparison.files == []

      assert %{
               status: :available,
               executable_lines: 0,
               files: [],
               skipped: [%{path: "Sources/API/Client.swift", reason: :excluded}]
             } =
               comparison.patch

      assert comparison.gaps == []
    end

    test "leaves out of the patch the files it cannot map to the commit's lines", %{
      project: project,
      account: account
    } do
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
        pr_run(project, account, base_files(), %{
          history_source: "none",
          merge_base_sha: "",
          history_fallback_reason: "not a git checkout"
        })

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

    test "describes a run without a commit alone", %{project: project, account: account} do
      run = CoverageFixtures.run_with_coverage(project, account, base_files(), %{git_commit_sha: ""})

      assert {:error, %{kind: :no_history, commit: ""} = reason} = Comparison.baseline(project, run)
      assert Comparison.reason_text(reason) == "the commit is unknown"

      comparison = Comparison.compare(project, run)
      assert {comparison.commit.sha, comparison.commit.coverage, comparison.baseline} == {"", 75.0, nil}
      assert comparison.patch.reason == :no_history
    end

    test "is nil for a commit without coverage", %{project: project, account: account} do
      run = CoverageFixtures.run_with_coverage(project, account, [], %{git_commit_sha: "c"})
      assert Comparison.compare(project, run) == nil
    end
  end

  describe "compare/3 on a partially measured commit" do
    setup %{project: project, account: account} do
      seed_history(account)
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

      assert comparison.commit.partial
      assert comparison.commit.partial_schemes == ["App"]
      assert comparison.baseline.commit == "b"
      assert comparison.total_delta == nil

      assert [%{scheme: "App", partial: true, coverage: 16.7, baseline_coverage: 75.0, delta: nil}] =
               comparison.schemes

      assert [
               %{name: "Calculator", delta: -41.7},
               %{name: "Formatter", coverage: +0.0, baseline_coverage: 100.0, delta: nil}
             ] = comparison.targets

      assert [%{path: "Sources/Add.swift", delta: -75.0}] = comparison.files
    end

    test "still computes the patch, over the lines the tests that ran covered", %{project: project, pr: pr} do
      %{patch: patch} = Comparison.compare(project, pr)
      assert {patch.status, patch.covered_lines, patch.executable_lines} == {:available, 1, 2}
    end
  end
end
