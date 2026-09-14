defmodule Tuist.Tests.XcodeCoverageTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Tests
  alias Tuist.Tests.XcodeCoverage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{account: account, project: project}
  end

  defp file(path, blob, targets, lines, functions \\ []) do
    %{
      path: path,
      git_blob_id: blob,
      targets: targets,
      covered_lines: Enum.count(lines, fn {_line, count} -> count > 0 end),
      executable_lines: length(lines),
      line_numbers: Enum.map(lines, &elem(&1, 0)),
      execution_counts: Enum.map(lines, &elem(&1, 1)),
      functions: functions
    }
  end

  defp coverage(files, opts \\ []) do
    %{
      partial: Keyword.get(opts, :partial, false),
      files: files,
      unobserved_files: Keyword.get(opts, :unobserved_files, [])
    }
  end

  defp add do
    file(
      "Sources/Calculator/Add.swift",
      "add1",
      ["Calculator", "CalculatorTests"],
      [{2, 3}, {3, 0}, {4, 0}, {6, 1}, {7, 0}],
      [%{name: "add(_:_:)", line_number: 2, execution_count: 3, covered_lines: 2, executable_lines: 5}]
    )
  end

  defp untested, do: file("Sources/Calculator/Untested.swift", "untested1", ["Calculator"], [{2, 0}, {3, 0}])
  defp formatter, do: file("Sources/Formatter/Formatter.swift", "formatter1", ["Formatter"], [{1, 2}, {2, 2}])

  defp create_test(project, account, attrs) do
    Tests.create_test(
      Map.merge(
        %{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account.id,
          duration: 1000,
          status: "success",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: []
        },
        attrs
      )
    )
  end

  describe "create_test/1 with xcode_coverage" do
    test "stores every observed file with its lines and the run's totals", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add(), untested(), formatter()])})

      assert {:ok, stored} = Tests.get_test(test.id)
      assert {stored.coverage_covered_lines, stored.coverage_executable_lines} == {4, 9}
      assert {stored.coverage_observed_covered_lines, stored.coverage_observed_executable_lines} == {4, 9}
      assert stored.coverage_carried_forward_files == 0

      # A file compiled into several targets counts towards each of them.
      assert project.id
             |> XcodeCoverage.targets_for_run(test.id)
             |> Enum.map(&{&1.name, &1.files_count, &1.covered_lines, &1.executable_lines}) ==
               [{"Calculator", 2, 2, 7}, {"CalculatorTests", 1, 2, 5}, {"Formatter", 1, 2, 2}]

      {files, count} = XcodeCoverage.list_files(project.id, test.id, 1, 20)
      assert count == 3

      assert Enum.map(files, & &1.path) == [
               "Sources/Calculator/Untested.swift",
               "Sources/Calculator/Add.swift",
               "Sources/Formatter/Formatter.swift"
             ]

      assert Enum.all?(files, &(&1.observed and not &1.carried_forward))
    end

    test "describes one file's lines, uncovered ranges and functions", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})

      detail = XcodeCoverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")

      assert detail.source == "observed"
      assert detail.git_blob_id == "add1"
      assert detail.targets == ["Calculator", "CalculatorTests"]
      assert {detail.covered_lines, detail.executable_lines} == {2, 5}
      # Lines 3 and 4 run together; 5 is not executable, so 7 starts its own range after 6 ran.
      assert detail.uncovered_ranges == [{3, 4}, {7, 7}]
      assert [%{name: "add(_:_:)", execution_count: 3}] = detail.functions
      assert XcodeCoverage.file_detail(project.id, test.id, "Missing.swift") == nil
    end

    test "leaves a run without coverage untouched", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{})

      assert {:ok, stored} = Tests.get_test(test.id)
      assert stored.coverage_executable_lines == 0
      assert XcodeCoverage.targets_for_run(project.id, test.id) == []
    end
  end

  describe "partial runs" do
    test "carry forward earlier evidence for unchanged files where it covers lines the run did not", %{
      project: project,
      account: account
    } do
      {:ok, full} = create_test(project, account, %{xcode_coverage: coverage([add(), untested(), formatter()])})

      # Only a test that reaches line 2 of the unchanged add file ran; the formatter's target
      # was not built at all; the untested file changed since, so its old evidence no longer
      # describes it.
      partial_add = file("Sources/Calculator/Add.swift", "add1", ["Calculator"], [{2, 1}, {3, 0}, {4, 0}, {6, 0}, {7, 0}])

      {:ok, partial} =
        create_test(project, account, %{
          xcode_coverage:
            coverage([partial_add],
              partial: true,
              unobserved_files: [
                %{path: "Sources/Formatter/Formatter.swift", git_blob_id: "formatter1"},
                %{path: "Sources/Calculator/Untested.swift", git_blob_id: "untested2"},
                %{path: "README.swift", git_blob_id: "never-observed"}
              ]
            )
        })

      assert {:ok, stored} = Tests.get_test(partial.id)
      assert {stored.coverage_observed_covered_lines, stored.coverage_observed_executable_lines} == {1, 5}
      assert {stored.coverage_covered_lines, stored.coverage_executable_lines} == {4, 7}
      assert stored.coverage_carried_forward_files == 2

      {files, 2} = XcodeCoverage.list_files(project.id, partial.id, 1, 20)

      assert Enum.map(files, &{&1.path, &1.observed, &1.carried_forward, &1.covered_lines}) == [
               {"Sources/Calculator/Add.swift", true, true, 2},
               {"Sources/Formatter/Formatter.swift", false, true, 2}
             ]

      add_detail = XcodeCoverage.file_detail(project.id, partial.id, "Sources/Calculator/Add.swift")
      assert add_detail.source == "observed_and_carried_forward"
      assert add_detail.source_test_run_id == full.id
      assert add_detail.uncovered_ranges == [{3, 4}, {7, 7}]

      formatter_detail = XcodeCoverage.file_detail(project.id, partial.id, "Sources/Formatter/Formatter.swift")
      assert formatter_detail.source == "carried_forward"

      # Evidence that covers nothing the run did not is not worth a row.
      assert %{carried_forward: []} =
               XcodeCoverage.evidence(project.id, UUIDv7.generate(), coverage([add()], partial: true))
    end

    test "never carry anything forward for a run that ran every test", %{project: project, account: account} do
      {:ok, _full} = create_test(project, account, %{xcode_coverage: coverage([formatter()])})

      {:ok, run} =
        create_test(project, account, %{
          xcode_coverage:
            coverage([add()], unobserved_files: [%{path: "Sources/Formatter/Formatter.swift", git_blob_id: "formatter1"}])
        })

      assert {:ok, %{coverage_carried_forward_files: 0, coverage_executable_lines: 5}} = Tests.get_test(run.id)
    end
  end

  describe "sharded runs" do
    test "merge the shards' lines with the evidence carried forward", %{
      project: project,
      account: account
    } do
      {:ok, _earlier} = create_test(project, account, %{xcode_coverage: coverage([formatter()])})
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})
      {:ok, stored} = Tests.get_test(test.id)

      # A second shard ran other tests over the same file, and carried the formatter forward
      # before a third shard observed it.
      other_shard =
        coverage(
          [file("Sources/Calculator/Add.swift", "add1", ["CalculatorTests"], [{2, 1}, {3, 5}, {4, 0}, {6, 0}, {7, 0}])],
          partial: true,
          unobserved_files: [%{path: "Sources/Formatter/Formatter.swift", git_blob_id: "formatter1"}]
        )

      evidence = XcodeCoverage.evidence(project.id, test.id, other_shard)
      assert [%{source: "carried_forward"}] = evidence.carried_forward
      XcodeCoverage.insert_files(stored, evidence)

      assert %{
               coverage_covered_lines: 5,
               coverage_executable_lines: 7,
               coverage_observed_covered_lines: 3,
               coverage_carried_forward_files: 1
             } =
               XcodeCoverage.merge_run_attrs(stored, evidence)

      third_shard = coverage([file("Sources/Formatter/Formatter.swift", "formatter1", ["Formatter"], [{1, 0}, {2, 0}])])
      evidence = XcodeCoverage.evidence(project.id, test.id, third_shard)
      XcodeCoverage.insert_files(stored, evidence)

      # The formatter's own shard ran none of its lines; the evidence carried forward still counts.
      assert %{
               coverage_covered_lines: 5,
               coverage_observed_covered_lines: 3,
               coverage_observed_executable_lines: 7,
               coverage_carried_forward_files: 1
             } = XcodeCoverage.merge_run_attrs(stored, evidence)

      detail = XcodeCoverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")
      assert Enum.take(detail.lines, 2) == [{2, 4}, {3, 5}]
      assert detail.uncovered_ranges == [{4, 4}, {7, 7}]
    end
  end

  describe "percentage/2" do
    test "rounds to one decimal and survives a target with no executable lines" do
      assert XcodeCoverage.percentage(1, 3) == 33.3
      assert XcodeCoverage.percentage(0, 0) == 0.0
    end
  end
end
