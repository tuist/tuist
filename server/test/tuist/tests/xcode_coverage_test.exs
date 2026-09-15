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
    %{partial: Keyword.get(opts, :partial, false), files: files}
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
      refute stored.coverage_partial

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

      assert Enum.map(files, & &1.git_blob_id) == ["untested1", "add1", "formatter1"]
    end

    test "describes one file's lines, uncovered ranges and functions", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})

      detail = XcodeCoverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")

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

  describe "the xcode_coverage feature flag" do
    test "drops the coverage of an account that does not have it", %{project: project, account: account} do
      stub(Tuist.FeatureFlags, :xcode_coverage_enabled?, fn _account -> false end)

      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})

      assert {:ok, stored} = Tests.get_test(test.id)
      assert stored.coverage_executable_lines == 0
      assert {[], 0} = XcodeCoverage.list_files(project.id, test.id, 1, 20)
    end
  end

  describe "partial runs" do
    test "are marked partial and never borrow coverage from earlier runs", %{project: project, account: account} do
      {:ok, _full} = create_test(project, account, %{xcode_coverage: coverage([add(), untested(), formatter()])})

      partial_add = file("Sources/Calculator/Add.swift", "add1", ["Calculator"], [{2, 1}, {3, 0}, {4, 0}, {6, 0}, {7, 0}])
      {:ok, partial} = create_test(project, account, %{xcode_coverage: coverage([partial_add], partial: true)})

      assert {:ok, stored} = Tests.get_test(partial.id)
      assert stored.coverage_partial
      assert {stored.coverage_covered_lines, stored.coverage_executable_lines} == {1, 5}

      assert {[%{path: "Sources/Calculator/Add.swift", covered_lines: 1}], 1} =
               XcodeCoverage.list_files(project.id, partial.id, 1, 20)
    end
  end

  describe "sharded runs" do
    test "merge the shards' lines and stay partial once any shard was", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: coverage([add()])})
      {:ok, stored} = Tests.get_test(test.id)

      # Another shard ran other tests over the same file.
      other_shard =
        coverage(
          [file("Sources/Calculator/Add.swift", "add1", ["CalculatorTests"], [{2, 1}, {3, 5}, {4, 0}, {6, 0}, {7, 0}])],
          partial: true
        )

      rows = XcodeCoverage.rows(project.id, other_shard)
      XcodeCoverage.insert_files(stored, rows)

      assert %{coverage_covered_lines: 3, coverage_executable_lines: 5, coverage_partial: true} =
               XcodeCoverage.merge_run_attrs(stored, rows)

      detail = XcodeCoverage.file_detail(project.id, test.id, "Sources/Calculator/Add.swift")
      assert Enum.take(detail.lines, 2) == [{2, 4}, {3, 5}]
      assert detail.uncovered_ranges == [{4, 4}, {7, 7}]
      assert detail.targets == ["Calculator", "CalculatorTests"]
    end
  end

  describe "percentage/2" do
    test "rounds to one decimal and survives a target with no executable lines" do
      assert XcodeCoverage.percentage(1, 3) == 33.3
      assert XcodeCoverage.percentage(0, 0) == 0.0
    end
  end
end
