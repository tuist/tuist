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

  # `xccov` lists Add.swift under the framework and again under the test bundle
  # that links it statically, so a naive sum would count it twice.
  @coverage %{
    targets: [
      %{
        name: "Calculator",
        covered_lines: 5,
        executable_lines: 17,
        files: [
          %{path: "Sources/Calculator/Add.swift", covered_lines: 5, executable_lines: 11},
          %{path: "Sources/Calculator/Untested.swift", covered_lines: 0, executable_lines: 6}
        ]
      },
      %{
        name: "CalculatorTests",
        covered_lines: 13,
        executable_lines: 19,
        files: [
          %{path: "Sources/Calculator/Add.swift", covered_lines: 5, executable_lines: 11},
          %{path: "Tests/CalculatorTests.swift", covered_lines: 8, executable_lines: 8}
        ]
      }
    ]
  }

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

  describe "run_attrs/1" do
    test "counts each path once across targets" do
      assert XcodeCoverage.run_attrs(@coverage) == %{
               coverage_covered_lines: 13,
               coverage_executable_lines: 25
             }
    end

    test "leaves the columns to their defaults without coverage" do
      assert XcodeCoverage.run_attrs(nil) == %{}
    end
  end

  describe "create_test/1 with xcode_coverage" do
    test "stores the totals on the run and every file under its target", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: @coverage})

      assert {:ok, stored} = Tests.get_test(test.id)
      assert stored.coverage_covered_lines == 13
      assert stored.coverage_executable_lines == 25

      targets = XcodeCoverage.targets_for_run(test.id)

      assert Enum.map(targets, &{&1.name, &1.covered_lines, &1.executable_lines}) == [
               {"Calculator", 5, 17},
               {"CalculatorTests", 13, 19}
             ]

      assert Enum.map(targets, & &1.files_count) == [2, 2]

      # Least covered first, so the gaps surface at the top; the shared file
      # appears once per target it was reported under.
      {files, meta} = XcodeCoverage.list_files(test.id, 1, 20)
      assert meta == %{current_page: 1, total_pages: 1}

      assert Enum.map(files, &{&1.target_name, &1.path}) == [
               {"Calculator", "Sources/Calculator/Untested.swift"},
               {"Calculator", "Sources/Calculator/Add.swift"},
               {"CalculatorTests", "Sources/Calculator/Add.swift"},
               {"CalculatorTests", "Tests/CalculatorTests.swift"}
             ]
    end

    test "pages the files", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: @coverage})

      {page_one, meta} = XcodeCoverage.list_files(test.id, 1, 3)
      {page_two, _} = XcodeCoverage.list_files(test.id, 2, 3)

      assert meta.total_pages == 2
      assert length(page_one) == 3
      assert Enum.map(page_two, & &1.path) == ["Tests/CalculatorTests.swift"]
    end

    test "a later shard never shrinks the totals the run already carries", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{xcode_coverage: @coverage})
      {:ok, stored} = Tests.get_test(test.id)

      smaller = %{
        targets: [
          %{
            name: "Calculator",
            covered_lines: 1,
            executable_lines: 11,
            files: [%{path: "Sources/Calculator/Add.swift", covered_lines: 1, executable_lines: 11}]
          }
        ]
      }

      assert XcodeCoverage.merge_run_attrs(stored, smaller) == %{
               coverage_covered_lines: 13,
               coverage_executable_lines: 25
             }
    end

    test "leaves a run without coverage untouched", %{project: project, account: account} do
      {:ok, test} = create_test(project, account, %{})

      assert {:ok, stored} = Tests.get_test(test.id)
      assert stored.coverage_covered_lines == 0
      assert stored.coverage_executable_lines == 0
      assert XcodeCoverage.targets_for_run(test.id) == []
    end
  end

  describe "percentage/2" do
    test "rounds to one decimal and survives a target with no executable lines" do
      assert XcodeCoverage.percentage(1, 3) == 33.3
      assert XcodeCoverage.percentage(0, 0) == 0.0
    end
  end
end
