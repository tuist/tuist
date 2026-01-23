defmodule Tuist.RunsTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.IngestRepo
  alias Tuist.Runs
  alias Tuist.Runs.TestCase
  alias Tuist.Runs.TestCaseEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "create_build/1" do
    test "creates a build" do
      # Given
      project_id = ProjectsFixtures.project_fixture().id
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      # When
      {:ok, build} =
        Runs.create_build(%{
          id: UUIDv7.generate(),
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "Mac15,6",
          scheme: "App",
          project_id: project_id,
          account_id: account_id,
          status: "success",
          issues: [],
          files: [],
          targets: []
        })

      # Then
      assert build.duration == 1000
      assert build.macos_version == "11.2.3"
      assert build.xcode_version == "12.4"
      assert build.is_ci == false
      assert build.model_identifier == "Mac15,6"
      assert build.scheme == "App"
      assert build.project_id == project_id
      assert build.account_id == account_id
      assert build.status == :success
    end

    test "creates a build with cacheable tasks and calculates counts correctly" do
      # Given
      project_id = ProjectsFixtures.project_fixture().id
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      cacheable_tasks = [
        %{type: :swift, status: :hit_local, key: "task1"},
        %{type: :swift, status: :hit_remote, key: "task2"},
        %{type: :clang, status: :miss, key: "task3"},
        %{type: :swift, status: :hit_local, key: "task4"},
        %{type: :clang, status: :hit_remote, key: "task5"}
      ]

      # When
      {:ok, build} =
        Runs.create_build(%{
          id: UUIDv7.generate(),
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "Mac15,6",
          scheme: "App",
          project_id: project_id,
          account_id: account_id,
          status: "success",
          issues: [],
          files: [],
          targets: [],
          cacheable_tasks: cacheable_tasks
        })

      # Then
      assert build.cacheable_tasks_count == 5
      assert build.cacheable_task_local_hits_count == 2
      assert build.cacheable_task_remote_hits_count == 2
    end

    test "creates a build with empty cacheable tasks" do
      # Given
      project_id = ProjectsFixtures.project_fixture().id
      account_id = AccountsFixtures.user_fixture(preload: [:account]).account.id

      # When
      {:ok, build} =
        Runs.create_build(%{
          id: UUIDv7.generate(),
          duration: 1000,
          macos_version: "11.2.3",
          xcode_version: "12.4",
          is_ci: false,
          model_identifier: "Mac15,6",
          scheme: "App",
          project_id: project_id,
          account_id: account_id,
          status: "success",
          issues: [],
          files: [],
          targets: [],
          cacheable_tasks: []
        })

      # Then
      assert build.cacheable_tasks_count == 0
      assert build.cacheable_task_local_hits_count == 0
      assert build.cacheable_task_remote_hits_count == 0
    end
  end

  describe "build/1" do
    test "returns build" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture()

      build_id = build.id

      # When
      build = Runs.get_build(build_id)

      # Then
      assert build.id == build_id
    end

    test "returns nil when build does not exist" do
      # Given
      non_existent_build_id = UUIDv7.generate()

      # When
      build = Runs.get_build(non_existent_build_id)

      # Then
      assert build == nil
    end
  end

  describe "get_test/1" do
    test "returns test when it exists" do
      # Given
      {:ok, test} = RunsFixtures.test_fixture()
      test_id = test.id

      # When
      result = Runs.get_test(test_id)

      # Then
      assert {:ok, found_test} = result
      assert found_test.id == test_id
    end

    test "returns error when test does not exist" do
      # Given
      non_existent_test_id = UUIDv7.generate()

      # When
      result = Runs.get_test(non_existent_test_id)

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "get_latest_test_by_build_run_id/1" do
    test "returns test when it exists for build" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture()

      {:ok, test} =
        RunsFixtures.test_fixture(
          build_run_id: build.id,
          ran_at: ~N[2024-03-04 01:00:00]
        )

      # When
      result = Runs.get_latest_test_by_build_run_id(build.id)

      # Then
      assert {:ok, found_test} = result
      assert found_test.id == test.id
      assert found_test.build_run_id == build.id
    end

    test "returns the latest test when multiple tests exist for build" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture()

      {:ok, _older_test} =
        RunsFixtures.test_fixture(
          build_run_id: build.id,
          ran_at: ~N[2024-03-04 01:00:00]
        )

      {:ok, latest_test} =
        RunsFixtures.test_fixture(
          build_run_id: build.id,
          ran_at: ~N[2024-03-04 02:00:00]
        )

      # When
      result = Runs.get_latest_test_by_build_run_id(build.id)

      # Then
      assert {:ok, found_test} = result
      assert found_test.id == latest_test.id
    end

    test "returns error when no test exists for build" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture()

      # When
      result = Runs.get_latest_test_by_build_run_id(build.id)

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "list_test_runs/1" do
    test "lists test runs with pagination" do
      # Given
      project = ProjectsFixtures.project_fixture()
      project_two = ProjectsFixtures.project_fixture()

      {:ok, test_one} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          duration: 1000,
          ran_at: ~N[2024-03-04 01:00:00]
        )

      RunsFixtures.test_fixture(project_id: project_two.id)

      {:ok, test_two} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          duration: 2000,
          ran_at: ~N[2024-03-04 02:00:00]
        )

      # When
      {got_tests_first_page, got_meta_first_page} =
        Runs.list_test_runs(%{
          page_size: 1,
          filters: [%{field: :project_id, op: :==, value: project.id}],
          order_by: [:ran_at],
          order_directions: [:desc]
        })

      {got_tests_second_page, _meta} =
        Runs.list_test_runs(Flop.to_next_page(got_meta_first_page.flop))

      # Then
      assert length(got_tests_first_page) == 1
      assert length(got_tests_second_page) == 1
      assert hd(got_tests_first_page).id == test_two.id
      assert hd(got_tests_second_page).id == test_one.id
    end

    test "filters by status" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, _success_test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          status: "success"
        )

      {:ok, failure_test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          status: "failure"
        )

      # When
      {tests, _meta} =
        Runs.list_test_runs(%{
          filters: [
            %{field: :project_id, op: :==, value: project.id},
            %{field: :status, op: :==, value: "failure"}
          ]
        })

      # Then
      assert length(tests) == 1
      assert hd(tests).id == failure_test.id
    end

    test "returns empty list when no tests exist for project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      {tests, meta} =
        Runs.list_test_runs(%{
          filters: [%{field: :project_id, op: :==, value: project.id}]
        })

      # Then
      assert tests == []
      assert meta.total_count == 0
    end
  end

  describe "list_test_case_runs/1" do
    test "lists test case runs with pagination" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "testCase1", status: "success", duration: 100},
                %{name: "testCase2", status: "failure", duration: 200},
                %{name: "testCase3", status: "success", duration: 300}
              ]
            }
          ]
        )

      # When
      {test_cases_first_page, meta_first_page} =
        Runs.list_test_case_runs(%{
          page_size: 2,
          filters: [%{field: :test_run_id, op: :==, value: test.id}],
          order_by: [:name],
          order_directions: [:asc]
        })

      {test_cases_second_page, _meta} =
        Runs.list_test_case_runs(Flop.to_next_page(meta_first_page.flop))

      # Then
      assert length(test_cases_first_page) == 2
      assert length(test_cases_second_page) == 1
      assert meta_first_page.total_count == 3
    end

    test "filters by status" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "successTest", status: "success", duration: 100},
                %{name: "failureTest", status: "failure", duration: 200},
                %{name: "skippedTest", status: "skipped", duration: 0}
              ]
            }
          ]
        )

      # When
      {test_cases, _meta} =
        Runs.list_test_case_runs(%{
          filters: [
            %{field: :test_run_id, op: :==, value: test.id},
            %{field: :status, op: :==, value: "failure"}
          ]
        })

      # Then
      assert length(test_cases) == 1
      assert hd(test_cases).name == "failureTest"
    end

    test "returns empty list when no test cases exist for test run" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "EmptyModule",
              status: "success",
              duration: 0,
              test_cases: []
            }
          ]
        )

      # When
      {test_cases, meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      # Then
      assert test_cases == []
      assert meta.total_count == 0
    end
  end

  describe "get_test_run_failures_count/1" do
    test "returns count of failures for a test run" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 1000,
              test_cases: [
                %{
                  name: "testWithFailure",
                  status: "failure",
                  duration: 200,
                  failures: [
                    %{
                      message: "Assertion failed",
                      path: "/path/to/test.swift",
                      line_number: 42,
                      issue_type: "assertion"
                    },
                    %{
                      message: "Another failure",
                      path: "/path/to/test.swift",
                      line_number: 50,
                      issue_type: "assertion"
                    }
                  ]
                },
                %{
                  name: "testWithSingleFailure",
                  status: "failure",
                  duration: 100,
                  failures: [
                    %{
                      message: "Test failed",
                      path: "/path/to/test.swift",
                      line_number: 30,
                      issue_type: "error"
                    }
                  ]
                }
              ]
            }
          ]
        )

      # When
      count = Runs.get_test_run_failures_count(test.id)

      # Then
      assert count == 3
    end

    test "returns 0 when no failures exist for test run" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "successTest", status: "success", duration: 100}
              ]
            }
          ]
        )

      # When
      count = Runs.get_test_run_failures_count(test.id)

      # Then
      assert count == 0
    end
  end

  describe "list_test_run_failures/2" do
    test "lists failures for a test run with pagination" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 1000,
              test_cases: [
                %{
                  name: "testCase1",
                  status: "failure",
                  duration: 200,
                  failures: [
                    %{
                      message: "Failure 1",
                      path: "/path/to/test.swift",
                      line_number: 10,
                      issue_type: "assertion"
                    }
                  ]
                },
                %{
                  name: "testCase2",
                  status: "failure",
                  duration: 300,
                  failures: [
                    %{
                      message: "Failure 2",
                      path: "/path/to/test.swift",
                      line_number: 20,
                      issue_type: "error"
                    },
                    %{
                      message: "Failure 3",
                      path: "/path/to/test.swift",
                      line_number: 30,
                      issue_type: "assertion"
                    }
                  ]
                }
              ]
            }
          ]
        )

      # When
      {failures_page1, meta_page1} =
        Runs.list_test_run_failures(test.id, %{
          page_size: 2
        })

      {failures_page2, _meta} =
        Runs.list_test_run_failures(test.id, Flop.to_next_page(meta_page1.flop))

      # Then
      assert length(failures_page1) == 2
      assert length(failures_page2) == 1
      assert meta_page1.total_count == 3
    end

    test "returns empty list when no failures exist for test run" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "successTest", status: "success", duration: 100}
              ]
            }
          ]
        )

      # When
      {failures, meta} = Runs.list_test_run_failures(test.id, %{})

      # Then
      assert failures == []
      assert meta.total_count == 0
    end
  end

  describe "list_test_suite_runs/1" do
    test "lists test suite runs with pagination" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_suites: [
                %{name: "Suite1", status: "success", duration: 300},
                %{name: "Suite2", status: "failure", duration: 400},
                %{name: "Suite3", status: "success", duration: 300}
              ],
              test_cases: []
            }
          ]
        )

      # When
      {suites_page1, meta_page1} =
        Runs.list_test_suite_runs(%{
          page_size: 2,
          filters: [%{field: :test_run_id, op: :==, value: test.id}],
          order_by: [:name],
          order_directions: [:asc]
        })

      {suites_page2, _meta} =
        Runs.list_test_suite_runs(Flop.to_next_page(meta_page1.flop))

      # Then
      assert length(suites_page1) == 2
      assert length(suites_page2) == 1
      assert meta_page1.total_count == 3
    end

    test "filters by status" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_suites: [
                %{name: "SuccessSuite", status: "success", duration: 200},
                %{name: "FailureSuite", status: "failure", duration: 300}
              ],
              test_cases: []
            }
          ]
        )

      # When
      {suites, _meta} =
        Runs.list_test_suite_runs(%{
          filters: [
            %{field: :test_run_id, op: :==, value: test.id},
            %{field: :status, op: :==, value: "failure"}
          ]
        })

      # Then
      assert length(suites) == 1
      assert hd(suites).name == "FailureSuite"
      assert hd(suites).status == "failure"
    end

    test "returns empty list when no test suites exist for test run" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: []
            }
          ]
        )

      # When
      {suites, meta} =
        Runs.list_test_suite_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      # Then
      assert suites == []
      assert meta.total_count == 0
    end
  end

  describe "create_test/1" do
    test "creates a test with basic attributes" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1500,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "abc123def456",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true
      }

      # When
      {:ok, test} = Runs.create_test(test_attrs)

      # Then
      assert test.id == test_attrs.id
      assert test.project_id == project.id
      assert test.account_id == account.id
      assert test.duration == 1500
      assert test.status == "success"
      assert test.model_identifier == "Mac15,6"
      assert test.macos_version == "14.0"
      assert test.xcode_version == "15.0"
      assert test.git_branch == "main"
      assert test.git_commit_sha == "abc123def456"
      assert test.is_ci == true
    end

    test "creates a test with test modules and test cases" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 2000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "develop",
        git_commit_sha: "xyz789",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: false,
        test_modules: [
          %{
            name: "MyTestModule",
            status: "success",
            duration: 1000,
            test_cases: [
              %{name: "testExample1", status: "success", duration: 300},
              %{name: "testExample2", status: "success", duration: 700}
            ]
          }
        ]
      }

      # When
      {:ok, test} = Runs.create_test(test_attrs)

      # Then
      assert test.id == test_attrs.id

      # Verify test module was created
      {modules, _meta} =
        Runs.list_test_module_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(modules) == 1
      module = hd(modules)
      assert module.name == "MyTestModule"
      assert module.status == "success"
      assert module.test_case_count == 2

      {test_cases, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(test_cases) == 2
      case_names = Enum.map(test_cases, & &1.name)
      assert "testExample1" in case_names
      assert "testExample2" in case_names
    end

    test "creates a test with test suites" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 3000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "feature",
        git_commit_sha: "feature123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "TestModuleWithSuites",
            status: "success",
            duration: 2000,
            test_suites: [
              %{name: "UnitTests", status: "success", duration: 1000},
              %{name: "IntegrationTests", status: "success", duration: 1000}
            ],
            test_cases: [
              %{
                name: "testUnit1",
                test_suite_name: "UnitTests",
                status: "success",
                duration: 500
              },
              %{
                name: "testIntegration1",
                test_suite_name: "IntegrationTests",
                status: "success",
                duration: 800
              }
            ]
          }
        ]
      }

      # When
      {:ok, test} = Runs.create_test(test_attrs)

      # Then
      # Verify test suites were created
      {suites, _meta} =
        Runs.list_test_suite_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(suites) == 2
      suite_names = Enum.map(suites, & &1.name)
      assert "UnitTests" in suite_names
      assert "IntegrationTests" in suite_names

      # Verify test cases are linked to suites
      {test_cases, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(test_cases) == 2

      unit_test_case = Enum.find(test_cases, &(&1.name == "testUnit1"))
      assert unit_test_case.suite_name == "UnitTests"
      assert unit_test_case.test_suite_run_id

      integration_test_case = Enum.find(test_cases, &(&1.name == "testIntegration1"))
      assert integration_test_case.suite_name == "IntegrationTests"
      assert integration_test_case.test_suite_run_id
    end

    test "creates a CI test with empty test cases" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "abc123def456",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "EmptyModule",
            status: "success",
            duration: 0,
            test_cases: []
          }
        ]
      }

      # When / Then
      {:ok, test} = Runs.create_test(test_attrs)
      assert test.id == test_attrs.id
    end

    test "creates a CI test with a very large number of test cases" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_cases =
        for i <- 1..50_000 do
          %{
            name: "testCase#{i}",
            status: "success",
            duration: 100
          }
        end

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 5_000_000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "abc123def456",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "LargeTestModule",
            status: "success",
            duration: 5_000_000,
            test_cases: test_cases
          }
        ]
      }

      # When / Then
      {:ok, test} = Runs.create_test(test_attrs)
      assert test.id == test_attrs.id
    end

    test "creates a test with failures" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "failure",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "bugfix",
        git_commit_sha: "bugfix456",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "FailingTestModule",
            status: "failure",
            duration: 1000,
            test_cases: [
              %{
                name: "testThatFails",
                status: "failure",
                duration: 500,
                failures: [
                  %{
                    message: "Expected true but was false",
                    path: "/path/to/test.swift",
                    line_number: 42,
                    issue_type: "assertion"
                  }
                ]
              }
            ]
          }
        ]
      }

      # When
      {:ok, test} = Runs.create_test(test_attrs)

      # Then
      # Verify test was created with failure status
      assert test.status == "failure"

      # Verify failure was recorded
      count = Runs.get_test_run_failures_count(test.id)
      assert count == 1

      {failures, _meta} = Runs.list_test_run_failures(test.id, %{})
      assert length(failures) == 1

      failure = hd(failures)
      assert failure.message == "Expected true but was false"
      assert failure.path == "/path/to/test.swift"
      assert failure.line_number == 42
      assert failure.issue_type == "assertion"
      assert failure.test_case_name == "testThatFails"
      assert failure.test_module_name == "FailingTestModule"
    end
  end

  describe "list_test_module_runs/1" do
    test "lists test module runs with pagination" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{name: "ModuleA", status: "success", duration: 300, test_cases: []},
            %{name: "ModuleB", status: "failure", duration: 400, test_cases: []},
            %{name: "ModuleC", status: "success", duration: 500, test_cases: []}
          ]
        )

      # When
      {modules_page1, meta_page1} =
        Runs.list_test_module_runs(%{
          page_size: 2,
          filters: [%{field: :test_run_id, op: :==, value: test.id}],
          order_by: [:name],
          order_directions: [:asc]
        })

      {modules_page2, _meta} =
        Runs.list_test_module_runs(Flop.to_next_page(meta_page1.flop))

      # Then
      assert length(modules_page1) == 2
      assert length(modules_page2) == 1
      assert meta_page1.total_count == 3
    end

    test "filters by status" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{name: "SuccessModule", status: "success", duration: 200, test_cases: []},
            %{name: "FailureModule", status: "failure", duration: 300, test_cases: []}
          ]
        )

      # When
      {modules, _meta} =
        Runs.list_test_module_runs(%{
          filters: [
            %{field: :test_run_id, op: :==, value: test.id},
            %{field: :status, op: :==, value: "failure"}
          ]
        })

      # Then
      assert length(modules) == 1
      assert hd(modules).name == "FailureModule"
      assert hd(modules).status == "failure"
    end

    test "returns empty list when no test modules exist for test run" do
      # Given
      non_existent_test_id = UUIDv7.generate()

      # When
      {modules, meta} =
        Runs.list_test_module_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: non_existent_test_id}]
        })

      # Then
      assert modules == []
      assert meta.total_count == 0
    end
  end

  describe "list_build_runs/1" do
    test "lists build runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      project_two = ProjectsFixtures.project_fixture()

      {:ok, build_one} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          duration: 1000,
          inserted_at: ~U[2024-03-04 01:00:00Z]
        )

      RunsFixtures.build_fixture(project_id: project_two.id)

      {:ok, build_two} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          duration: 1000,
          inserted_at: ~U[2024-03-04 02:00:00Z]
        )

      # When
      {got_builds_first_page, got_meta_first_page} =
        Runs.list_build_runs(%{
          page_size: 1,
          filters: [%{field: :project_id, op: :==, value: project.id}],
          order_by: [:inserted_at],
          order_directions: [:desc]
        })

      {got_builds_second_page, _meta} =
        Runs.list_build_runs(Flop.to_next_page(got_meta_first_page.flop))

      # Then
      assert got_builds_first_page == [Repo.reload(build_two)]
      assert got_builds_second_page == [Repo.reload(build_one)]
    end
  end

  describe "project_build_schemes/1" do
    test "returns distinct schemes for the given project within the last 30 days" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      # Create builds with different schemes for the project
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App",
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "Framework",
        inserted_at: DateTime.utc_now()
      )

      # Create another build with a duplicate scheme (should be de-duped in the result)
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "App",
        inserted_at: DateTime.utc_now()
      )

      # Create a build with nil scheme (should be excluded)
      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: nil,
        inserted_at: DateTime.utc_now()
      )

      # Create a build for another project (should be excluded)
      RunsFixtures.build_fixture(
        project_id: other_project.id,
        scheme: "OtherApp",
        inserted_at: DateTime.utc_now()
      )

      # Create a build older than 30 days (should be excluded)
      old_date = DateTime.add(DateTime.utc_now(), -31, :day)

      RunsFixtures.build_fixture(
        project_id: project.id,
        scheme: "OldScheme",
        inserted_at: old_date
      )

      # When
      schemes = Runs.project_build_schemes(project)

      # Then
      assert schemes == ["App", "Framework"]
    end

    test "returns an empty list when no builds exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      schemes = Runs.project_build_schemes(project)

      # Then
      assert schemes == []
    end

    test "returns an empty list when only no schemes exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create a build with nil scheme
      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          scheme: nil,
          inserted_at: DateTime.utc_now()
        )

      # When
      schemes = Runs.project_build_schemes(project)

      # Then
      assert schemes == []
    end
  end

  describe "project_build_configurations/1" do
    test "returns distinct configurations for the given project within the last 30 days" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: "Debug",
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: "Release",
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: "Debug",
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: nil,
        inserted_at: DateTime.utc_now()
      )

      RunsFixtures.build_fixture(
        project_id: other_project.id,
        configuration: "Beta",
        inserted_at: DateTime.utc_now()
      )

      old_date = DateTime.add(DateTime.utc_now(), -31, :day)

      RunsFixtures.build_fixture(
        project_id: project.id,
        configuration: "OldConfiguration",
        inserted_at: old_date
      )

      # When
      configurations = Runs.project_build_configurations(project)

      # Then
      assert Enum.sort(configurations) == ["Debug", "Release"]
    end

    test "returns an empty list when no builds exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      configurations = Runs.project_build_configurations(project)

      # Then
      assert configurations == []
    end

    test "returns an empty list when only no configurations exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create a build with nil configuration
      {:ok, _build} =
        RunsFixtures.build_fixture(
          project_id: project.id,
          configuration: nil,
          inserted_at: DateTime.utc_now()
        )

      # When
      configurations = Runs.project_build_configurations(project)

      # Then
      assert configurations == []
    end
  end

  describe "recent_build_status_counts/2" do
    test "returns counts of successful and failed builds for the most recent builds" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 01:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "failure",
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 04:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: other_project.id,
        status: "failure",
        inserted_at: ~U[2024-01-01 05:00:00Z]
      )

      # When
      result = Runs.recent_build_status_counts(project.id, limit: 3)

      # Then
      assert result.successful_count == 2
      assert result.failed_count == 1
    end

    test "returns zero counts when no builds exist for the project" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      result = Runs.recent_build_status_counts(project.id)

      # Then
      assert result.successful_count == 0
      assert result.failed_count == 0
    end

    test "uses default limit of 40 when not specified" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for i <- 1..45 do
        status = if rem(i, 2) == 0, do: :success, else: :failure

        RunsFixtures.build_fixture(
          project_id: project.id,
          status: status,
          inserted_at: DateTime.add(~U[2024-01-01 00:00:00Z], i, :minute)
        )
      end

      # When
      result = Runs.recent_build_status_counts(project.id)

      # Then
      assert result.successful_count == 20
      assert result.failed_count == 20
    end

    test "respects custom limit parameter" do
      # Given
      project = ProjectsFixtures.project_fixture()

      for i <- 1..10 do
        status = if i <= 5, do: :success, else: :failure

        RunsFixtures.build_fixture(
          project_id: project.id,
          status: status,
          inserted_at: DateTime.add(~U[2024-01-01 00:00:00Z], i, :minute)
        )
      end

      # When
      result = Runs.recent_build_status_counts(project.id, limit: 5)

      # Then
      assert result.successful_count == 0
      assert result.failed_count == 5
    end

    test "orders by inserted_at descending to get most recent builds" do
      # Given
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 01:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "failure",
        inserted_at: ~U[2024-01-01 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: "success",
        inserted_at: ~U[2024-01-01 02:00:00Z]
      )

      # When
      result = Runs.recent_build_status_counts(project.id, limit: 2)

      # Then
      assert result.successful_count == 1
      assert result.failed_count == 1
    end
  end

  test "returns counts of successful and failed builds ordered by insertion time ascending" do
    # Given
    project = ProjectsFixtures.project_fixture()
    other_project = ProjectsFixtures.project_fixture()

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 01:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "failure",
      inserted_at: ~U[2024-01-01 02:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 03:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 04:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: other_project.id,
      status: "failure",
      inserted_at: ~U[2024-01-01 05:00:00Z]
    )

    # When
    result = Runs.recent_build_status_counts(project.id, limit: 3, order: :asc)

    # Then
    assert result.successful_count == 2
    assert result.failed_count == 1
  end

  test "supports ascending order with custom limit" do
    # Given
    project = ProjectsFixtures.project_fixture()

    for i <- 1..10 do
      status = if i <= 5, do: :success, else: :failure

      RunsFixtures.build_fixture(
        project_id: project.id,
        status: status,
        inserted_at: DateTime.add(~U[2024-01-01 00:00:00Z], i, :minute)
      )
    end

    # When
    result = Runs.recent_build_status_counts(project.id, limit: 5, order: :asc)

    # Then
    assert result.successful_count == 5
    assert result.failed_count == 0
  end

  test "orders by inserted_at ascending to get earliest builds" do
    # Given
    project = ProjectsFixtures.project_fixture()

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 03:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "failure",
      inserted_at: ~U[2024-01-01 01:00:00Z]
    )

    RunsFixtures.build_fixture(
      project_id: project.id,
      status: "success",
      inserted_at: ~U[2024-01-01 02:00:00Z]
    )

    # When
    result = Runs.recent_build_status_counts(project.id, limit: 2, order: :asc)

    # Then
    assert result.successful_count == 1
    assert result.failed_count == 1
  end

  describe "list_cacheable_tasks/1" do
    test "lists cacheable tasks with pagination" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cacheable_tasks: [
            %{type: :swift, status: :hit_local, key: "task1"},
            %{type: :swift, status: :hit_remote, key: "task2"},
            %{type: :clang, status: :miss, key: "task3"},
            %{type: :swift, status: :hit_local, key: "task4"}
          ]
        )

      # When
      {tasks, meta} =
        Runs.list_cacheable_tasks(%{
          page_size: 2,
          filters: [%{field: :build_run_id, op: :==, value: build.id}]
        })

      # Then
      assert length(tasks) == 2
      assert meta.total_count == 4
      assert meta.total_pages == 2
    end

    test "lists cacheable tasks with filters" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cacheable_tasks: [
            %{type: :swift, status: :hit_local, key: "swift_task"},
            %{type: :clang, status: :hit_remote, key: "clang_task"},
            %{type: :swift, status: :miss, key: "another_swift"}
          ]
        )

      # When - filter by type
      {swift_tasks, _meta} =
        Runs.list_cacheable_tasks(%{
          filters: [
            %{field: :build_run_id, op: :==, value: build.id},
            %{field: :type, op: :==, value: "swift"}
          ]
        })

      # Then
      assert length(swift_tasks) == 2
      assert Enum.all?(swift_tasks, &(&1.type == "swift"))
    end

    test "lists cacheable tasks with sorting by key ascending" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cacheable_tasks: [
            %{type: :swift, status: :hit_local, key: "zebra_task"},
            %{type: :swift, status: :hit_remote, key: "alpha_task"},
            %{type: :clang, status: :miss, key: "beta_task"}
          ]
        )

      # When
      {tasks, _meta} =
        Runs.list_cacheable_tasks(%{
          filters: [%{field: :build_run_id, op: :==, value: build.id}],
          order_by: [:key],
          order_directions: [:asc]
        })

      # Then
      keys = Enum.map(tasks, & &1.key)
      assert keys == ["alpha_task", "beta_task", "zebra_task"]
    end

    test "returns empty list when no cacheable tasks exist for build" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture(cacheable_tasks: [])

      # When
      {tasks, meta} =
        Runs.list_cacheable_tasks(%{
          filters: [%{field: :build_run_id, op: :==, value: build.id}]
        })

      # Then
      assert tasks == []
      assert meta.total_count == 0
    end
  end

  describe "build_ci_run_url/1" do
    test "returns GitHub Actions URL for GitHub provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :github,
          ci_run_id: "123456789",
          ci_project_handle: "owner/repo"
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == "https://github.com/owner/repo/actions/runs/123456789"
    end

    test "returns GitLab CI URL for GitLab provider with default host" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :gitlab,
          ci_run_id: "987654321",
          ci_project_handle: "namespace/project",
          ci_host: nil
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == "https://gitlab.com/namespace/project/-/pipelines/987654321"
    end

    test "returns GitLab CI URL for GitLab provider with custom host" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :gitlab,
          ci_run_id: "987654321",
          ci_project_handle: "namespace/project",
          ci_host: "gitlab.example.com"
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == "https://gitlab.example.com/namespace/project/-/pipelines/987654321"
    end

    test "returns Bitrise URL for Bitrise provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :bitrise,
          ci_run_id: "build-slug-123",
          ci_project_handle: "app-slug-456"
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == "https://app.bitrise.io/build/build-slug-123"
    end

    test "returns CircleCI URL for CircleCI provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :circleci,
          ci_run_id: "42",
          ci_project_handle: "owner/project"
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == "https://app.circleci.com/pipelines/github/owner/project/42"
    end

    test "returns Buildkite URL for Buildkite provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :buildkite,
          ci_run_id: "1234",
          ci_project_handle: "org/pipeline"
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == "https://buildkite.com/org/pipeline/builds/1234"
    end

    test "returns Codemagic URL for Codemagic provider" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :codemagic,
          ci_run_id: "build-id-123",
          ci_project_handle: "project-id-456"
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == "https://codemagic.io/app/project-id-456/build/build-id-123"
    end

    test "returns nil when ci_provider is nil" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: nil,
          ci_run_id: "123",
          ci_project_handle: "owner/repo"
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == nil
    end

    test "returns nil when ci_run_id is nil" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :github,
          ci_run_id: nil,
          ci_project_handle: "owner/repo"
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == nil
    end

    test "returns nil when ci_project_handle is nil" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: :github,
          ci_run_id: "123",
          ci_project_handle: nil
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == nil
    end

    test "returns nil when all CI fields are nil" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          ci_provider: nil,
          ci_run_id: nil,
          ci_project_handle: nil,
          ci_host: nil
        )

      # When
      url = Runs.build_ci_run_url(build)

      # Then
      assert url == nil
    end
  end

  describe "test_ci_run_url/1" do
    test "returns GitHub Actions URL for GitHub provider" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          ci_provider: "github",
          ci_run_id: "123456789",
          ci_project_handle: "owner/repo"
        )

      # When
      url = Runs.test_ci_run_url(test)

      # Then
      assert url == "https://github.com/owner/repo/actions/runs/123456789"
    end

    test "returns GitLab CI URL for GitLab provider with default host" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          ci_provider: "gitlab",
          ci_run_id: "987654321",
          ci_project_handle: "namespace/project",
          ci_host: nil
        )

      # When
      url = Runs.test_ci_run_url(test)

      # Then
      assert url == "https://gitlab.com/namespace/project/-/pipelines/987654321"
    end

    test "returns GitLab CI URL for GitLab provider with custom host" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          ci_provider: "gitlab",
          ci_run_id: "987654321",
          ci_project_handle: "namespace/project",
          ci_host: "gitlab.example.com"
        )

      # When
      url = Runs.test_ci_run_url(test)

      # Then
      assert url == "https://gitlab.example.com/namespace/project/-/pipelines/987654321"
    end

    test "returns Bitrise URL for Bitrise provider" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          ci_provider: "bitrise",
          ci_run_id: "build-slug-123",
          ci_project_handle: "app-slug-456"
        )

      # When
      url = Runs.test_ci_run_url(test)

      # Then
      assert url == "https://app.bitrise.io/build/build-slug-123"
    end

    test "returns CircleCI URL for CircleCI provider" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          ci_provider: "circleci",
          ci_run_id: "42",
          ci_project_handle: "owner/project"
        )

      # When
      url = Runs.test_ci_run_url(test)

      # Then
      assert url == "https://app.circleci.com/pipelines/github/owner/project/42"
    end

    test "returns Buildkite URL for Buildkite provider" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          ci_provider: "buildkite",
          ci_run_id: "1234",
          ci_project_handle: "org/pipeline"
        )

      # When
      url = Runs.test_ci_run_url(test)

      # Then
      assert url == "https://buildkite.com/org/pipeline/builds/1234"
    end

    test "returns Codemagic URL for Codemagic provider" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          ci_provider: "codemagic",
          ci_run_id: "build-id-123",
          ci_project_handle: "project-id-456"
        )

      # When
      url = Runs.test_ci_run_url(test)

      # Then
      assert url == "https://codemagic.io/app/project-id-456/build/build-id-123"
    end

    test "returns nil when ci_run_id is nil" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          ci_provider: "github",
          ci_run_id: nil,
          ci_project_handle: "owner/repo"
        )

      # When
      url = Runs.test_ci_run_url(test)

      # Then
      assert url == nil
    end
  end

  describe "cas_output_metrics/1" do
    test "returns correct metrics for build with CAS outputs" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 2000,
              duration: 2000,
              compressed_size: 1600,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 2000,
              duration: 2000,
              compressed_size: 1600,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node3",
              checksum: "ghi789",
              size: 2000,
              duration: 2000,
              compressed_size: 1600,
              operation: :upload,
              type: :swift
            }
          ]
        )

      # When
      metrics = Runs.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 2
      assert metrics.upload_count == 1
      assert metrics.download_bytes == 4000
      assert metrics.upload_bytes == 2000
      assert metrics.time_weighted_avg_download_throughput == 1000.0
      assert metrics.time_weighted_avg_upload_throughput == 1000.0
    end

    test "returns zeros for build with no CAS outputs" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture(cas_outputs: [])

      # When
      metrics = Runs.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 0
      assert metrics.upload_count == 0
      assert metrics.download_bytes == 0
      assert metrics.upload_bytes == 0
      assert metrics.time_weighted_avg_download_throughput == 0
      assert metrics.time_weighted_avg_upload_throughput == 0
    end

    test "returns zeros for non-existent build" do
      # Given
      non_existent_build_id = UUIDv7.generate()

      # When
      metrics = Runs.cas_output_metrics(non_existent_build_id)

      # Then
      assert metrics.download_count == 0
      assert metrics.upload_count == 0
      assert metrics.download_bytes == 0
      assert metrics.upload_bytes == 0
      assert metrics.time_weighted_avg_download_throughput == 0
      assert metrics.time_weighted_avg_upload_throughput == 0
    end

    test "handles only download operations" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 5000,
              duration: 5000,
              compressed_size: 4000,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 10_000,
              duration: 10_000,
              compressed_size: 8000,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      metrics = Runs.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 2
      assert metrics.upload_count == 0
      assert metrics.download_bytes == 15_000
      assert metrics.upload_bytes == 0
      # Time-weighted average: (5000 + 10000) / (5000 + 10000) * 1000 = 1000 bytes/s
      assert metrics.time_weighted_avg_download_throughput == 1000.0
      assert metrics.time_weighted_avg_upload_throughput == 0
    end

    test "handles only upload operations" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 8000,
              duration: 4000,
              compressed_size: 6400,
              operation: :upload,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 12_000,
              duration: 6000,
              compressed_size: 9600,
              operation: :upload,
              type: :swift
            }
          ]
        )

      # When
      metrics = Runs.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 0
      assert metrics.upload_count == 2
      assert metrics.download_bytes == 0
      assert metrics.upload_bytes == 20_000
      assert metrics.time_weighted_avg_download_throughput == 0
      # Time-weighted average: (8000 + 12000) / (4000 + 6000) * 1000 = 2000 bytes/s
      assert metrics.time_weighted_avg_upload_throughput == 2000.0
    end

    test "ignores operations with zero duration for throughput calculation" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 1000,
              duration: 0,
              compressed_size: 800,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 2000,
              duration: 2000,
              compressed_size: 1600,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      metrics = Runs.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 2
      assert metrics.upload_count == 0
      assert metrics.download_bytes == 3000
      assert metrics.upload_bytes == 0
      # Only the second operation (duration > 0) is included in throughput
      # Time-weighted average: 2000 / 2000 * 1000 = 1000 bytes/s
      assert metrics.time_weighted_avg_download_throughput == 1000.0
      assert metrics.time_weighted_avg_upload_throughput == 0
    end

    test "handles mixed operations with different throughputs" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 10_000,
              duration: 10_000,
              compressed_size: 8000,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 20_000,
              duration: 4000,
              compressed_size: 16_000,
              operation: :upload,
              type: :swift
            },
            %{
              node_id: "node3",
              checksum: "ghi789",
              size: 15_000,
              duration: 5000,
              compressed_size: 12_000,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      metrics = Runs.cas_output_metrics(build.id)

      # Then
      assert metrics.download_count == 2
      assert metrics.upload_count == 1
      assert metrics.download_bytes == 25_000
      assert metrics.upload_bytes == 20_000
      # Download throughput: (10000 + 15000) / (10000 + 5000) * 1000 = 1666.67 bytes/s
      assert_in_delta metrics.time_weighted_avg_download_throughput, 1666.67, 0.1
      # Upload throughput: 20000 / 4000 * 1000 = 5000 bytes/s
      assert metrics.time_weighted_avg_upload_throughput == 5000.0
    end
  end

  describe "cacheable_task_latency_metrics/1" do
    test "returns correct metrics for build with cacheable tasks with durations" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cacheable_tasks: [
            %{
              type: :swift,
              status: :hit_local,
              key: "task1",
              read_duration: 100.0,
              write_duration: nil
            },
            %{
              type: :swift,
              status: :miss,
              key: "task2",
              read_duration: nil,
              write_duration: 200.0
            },
            %{
              type: :clang,
              status: :hit_remote,
              key: "task3",
              read_duration: 150.0,
              write_duration: 250.0
            },
            %{
              type: :swift,
              status: :hit_local,
              key: "task4",
              read_duration: 200.0,
              write_duration: 300.0
            }
          ]
        )

      # When
      metrics = Runs.cacheable_task_latency_metrics(build.id)

      # Then
      assert metrics.avg_read_duration == 150.0
      assert metrics.avg_write_duration == 250.0
      assert metrics.p99_read_duration == 199.0
      assert metrics.p99_write_duration == 299.0
      assert metrics.p90_read_duration == 190.0
      assert metrics.p90_write_duration == 290.0
      assert metrics.p50_read_duration == 150.0
      assert metrics.p50_write_duration == 250.0
    end

    test "returns zeros for build with no cacheable tasks" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture(cacheable_tasks: [])

      # When
      metrics = Runs.cacheable_task_latency_metrics(build.id)

      # Then
      assert metrics.avg_read_duration == 0
      assert metrics.avg_write_duration == 0
      assert metrics.p99_read_duration == 0
      assert metrics.p99_write_duration == 0
      assert metrics.p90_read_duration == 0
      assert metrics.p90_write_duration == 0
      assert metrics.p50_read_duration == 0
      assert metrics.p50_write_duration == 0
    end
  end

  describe "get_cas_outputs_by_node_ids/3" do
    test "returns CAS outputs matching the given node_ids" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 1000,
              duration: 100,
              compressed_size: 800,
              operation: :download,
              type: :swift
            },
            %{
              node_id: "node2",
              checksum: "def456",
              size: 2000,
              duration: 200,
              compressed_size: 1600,
              operation: :upload,
              type: :swift
            },
            %{
              node_id: "node3",
              checksum: "ghi789",
              size: 3000,
              duration: 300,
              compressed_size: 2400,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      outputs = Runs.get_cas_outputs_by_node_ids(build.id, ["node1", "node3"])

      # Then
      assert length(outputs) == 2
      node_ids = Enum.map(outputs, & &1.node_id)
      assert "node1" in node_ids
      assert "node3" in node_ids
      refute "node2" in node_ids
    end

    test "returns empty list when node_ids is empty" do
      # Given
      {:ok, build} =
        RunsFixtures.build_fixture(
          cas_outputs: [
            %{
              node_id: "node1",
              checksum: "abc123",
              size: 1000,
              duration: 100,
              compressed_size: 800,
              operation: :download,
              type: :swift
            }
          ]
        )

      # When
      outputs = Runs.get_cas_outputs_by_node_ids(build.id, [])

      # Then
      assert outputs == []
    end

    test "returns all CAS outputs" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture()

      {:ok, _output1} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node1", operation: :download)
      {:ok, _output2} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node1", operation: :upload)
      {:ok, _output3} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node2", operation: :download)

      # When
      outputs = Runs.get_cas_outputs_by_node_ids(build.id, ["node1", "node2"])

      # Then
      assert length(outputs) == 3
      node_ids = Enum.map(outputs, & &1.node_id)
      assert Enum.count(node_ids, &(&1 == "node1")) == 2
      assert Enum.count(node_ids, &(&1 == "node2")) == 1
    end

    test "returns only distinct CAS outputs by node_id when distinct is true" do
      # Given
      {:ok, build} = RunsFixtures.build_fixture()

      {:ok, _output1} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node1", operation: :download)
      {:ok, _output2} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node1", operation: :upload)
      {:ok, _output3} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node2", operation: :download)
      {:ok, _output4} = RunsFixtures.cas_output_fixture(build_run_id: build.id, node_id: "node2", operation: :upload)

      # When
      outputs = Runs.get_cas_outputs_by_node_ids(build.id, ["node1", "node2"], distinct: true)

      # Then
      assert length(outputs) == 2
      node_ids = Enum.map(outputs, & &1.node_id)
      assert "node1" in node_ids
      assert "node2" in node_ids
    end
  end

  describe "list_test_cases/2" do
    test "returns empty list when no test cases exist" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      {test_cases, meta} = Runs.list_test_cases(project.id, %{})

      # Then
      assert test_cases == []
      assert meta.total_count == 0
    end

    test "supports pagination" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "testA", status: "success", duration: 100},
                %{name: "testB", status: "success", duration: 200},
                %{name: "testC", status: "success", duration: 300}
              ]
            }
          ]
        )

      # When
      {page1, meta} = Runs.list_test_cases(project.id, %{page: 1, page_size: 2})
      {page2, _meta2} = Runs.list_test_cases(project.id, %{page: 2, page_size: 2})

      # Then
      assert length(page1) == 2
      assert length(page2) == 1
      assert meta.total_count == 3
      assert meta.total_pages == 2
    end

    test "supports sorting by last_duration" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "slowTest", status: "success", duration: 500},
                %{name: "fastTest", status: "success", duration: 100},
                %{name: "mediumTest", status: "success", duration: 300}
              ]
            }
          ]
        )

      # When - sort by last_duration ascending
      {test_cases_asc, _meta} =
        Runs.list_test_cases(project.id, %{order_by: [:last_duration], order_directions: [:asc]})

      # Then
      assert Enum.at(test_cases_asc, 0).name == "fastTest"
      assert Enum.at(test_cases_asc, 2).name == "slowTest"

      # When - sort by last_duration descending
      {test_cases_desc, _meta} =
        Runs.list_test_cases(project.id, %{order_by: [:last_duration], order_directions: [:desc]})

      # Then
      assert Enum.at(test_cases_desc, 0).name == "slowTest"
      assert Enum.at(test_cases_desc, 2).name == "fastTest"
    end
  end

  describe "get_test_case_by_id/1" do
    test "returns {:ok, test_case} when test case exists" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_suites: [
                %{name: "TestSuite", status: "success", duration: 500}
              ],
              test_cases: [
                %{name: "testOne", test_suite_name: "TestSuite", status: "success", duration: 100}
              ]
            }
          ]
        )

      {[test_case], _meta} = Runs.list_test_cases(project.id, %{})

      # When
      result = Runs.get_test_case_by_id(test_case.id)

      # Then
      assert {:ok, found_test_case} = result
      assert found_test_case.id == test_case.id
      assert found_test_case.name == "testOne"
      assert found_test_case.module_name == "TestModule"
      assert found_test_case.suite_name == "TestSuite"
    end

    test "returns {:error, :not_found} when test case does not exist" do
      # Given
      non_existent_id = UUIDv7.generate()

      # When
      result = Runs.get_test_case_by_id(non_existent_id)

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "create_test/1 with repetitions (flaky tests)" do
    test "marks test case as flaky when repetitions have mixed results but final success" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 2000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "abc123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "FlakyTestModule",
            status: "success",
            duration: 2000,
            test_cases: [
              %{
                name: "testFlakyExample",
                status: "success",
                duration: 1000,
                repetitions: [
                  %{
                    repetition_number: 1,
                    name: "First Run",
                    status: "failure",
                    duration: 400
                  },
                  %{
                    repetition_number: 2,
                    name: "Retry 1",
                    status: "success",
                    duration: 600
                  }
                ],
                failures: [
                  %{
                    message: "Flaky assertion failed",
                    path: "/path/to/test.swift",
                    line_number: 10,
                    issue_type: "assertion"
                  }
                ]
              }
            ]
          }
        ]
      }

      # When
      {:ok, test} = Runs.create_test(test_attrs)

      # Then - test run should be marked as flaky with original status preserved
      assert test.status == "success"
      assert test.is_flaky == true

      {test_cases, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(test_cases) == 1
      flaky_case = hd(test_cases)
      assert flaky_case.name == "testFlakyExample"
      assert flaky_case.status == "success"
      assert flaky_case.is_flaky == true

      # Verify that a FlakyThresholdCheckWorker was enqueued to mark the test_case as flaky
      assert_enqueued(
        worker: Tuist.Alerts.Workers.FlakyThresholdCheckWorker,
        args: %{project_id: project.id, test_case_ids: [flaky_case.test_case_id]}
      )
    end

    test "marks test_case_run as flaky but not test_case for non-CI runs with repetitions" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 2000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "abc123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: false,
        test_modules: [
          %{
            name: "FlakyTestModule",
            status: "success",
            duration: 2000,
            test_cases: [
              %{
                name: "testFlakyNonCI",
                status: "success",
                duration: 1000,
                repetitions: [
                  %{
                    repetition_number: 1,
                    name: "First Run",
                    status: "failure",
                    duration: 400
                  },
                  %{
                    repetition_number: 2,
                    name: "Retry 1",
                    status: "success",
                    duration: 600
                  }
                ]
              }
            ]
          }
        ]
      }

      # When
      {:ok, test} = Runs.create_test(test_attrs)

      # Then - test run should NOT be marked as flaky for non-CI
      assert test.status == "success"
      assert test.is_flaky == false

      {test_case_runs, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(test_case_runs) == 1
      flaky_run = hd(test_case_runs)
      assert flaky_run.name == "testFlakyNonCI"
      assert flaky_run.status == "success"
      # TestCaseRun should still be marked as flaky based on repetitions
      assert flaky_run.is_flaky == true

      # But TestCase should NOT be marked as flaky (non-CI run)
      {:ok, test_case} = Runs.get_test_case_by_id(flaky_run.test_case_id)
      assert test_case.is_flaky == false
    end

    test "non-CI run does not clear existing flaky flag set by CI run" do
      # Given - first a CI run marks a test case as flaky
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      ci_test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 2000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "abc123",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
        is_ci: true,
        test_modules: [
          %{
            name: "FlakyTestModule",
            status: "success",
            duration: 2000,
            test_cases: [
              %{
                name: "testFlakyPreserved",
                status: "success",
                duration: 1000,
                repetitions: [
                  %{repetition_number: 1, name: "First Run", status: "failure", duration: 400},
                  %{repetition_number: 2, name: "Retry 1", status: "success", duration: 600}
                ]
              }
            ]
          }
        ]
      }

      {:ok, ci_test} = Runs.create_test(ci_test_attrs)

      # Get the test case ID from the CI run
      {ci_test_case_runs, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: ci_test.id}]
        })

      ci_run = hd(ci_test_case_runs)
      test_case_id = ci_run.test_case_id

      # Manually mark the test case as flaky (simulating what the FlakyThresholdCheckWorker would do)
      {:ok, _} = Runs.update_test_case(test_case_id, %{is_flaky: true}, project.id, %{type: :system, id: nil})

      # Verify TestCase is marked as flaky
      {:ok, test_case_after_ci} = Runs.get_test_case_by_id(test_case_id)
      assert test_case_after_ci.is_flaky == true

      # Now a non-CI run for the same test case (not flaky this time)
      non_ci_test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "def456",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: false,
        test_modules: [
          %{
            name: "FlakyTestModule",
            status: "success",
            duration: 1000,
            test_cases: [
              %{
                name: "testFlakyPreserved",
                status: "success",
                duration: 500
              }
            ]
          }
        ]
      }

      {:ok, _non_ci_test} = Runs.create_test(non_ci_test_attrs)

      # TestCase should STILL be marked as flaky (non-CI run should not clear it)
      {:ok, test_case_after_non_ci} = Runs.get_test_case_by_id(test_case_id)
      assert test_case_after_non_ci.is_flaky == true
    end

    test "keeps test case as success when all repetitions pass" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 2000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "abc123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "StableTestModule",
            status: "success",
            duration: 2000,
            test_cases: [
              %{
                name: "testStableExample",
                status: "success",
                duration: 1000,
                repetitions: [
                  %{
                    repetition_number: 1,
                    name: "First Run",
                    status: "success",
                    duration: 500
                  },
                  %{
                    repetition_number: 2,
                    name: "Retry 1",
                    status: "success",
                    duration: 500
                  }
                ]
              }
            ]
          }
        ]
      }

      # When
      {:ok, test} = Runs.create_test(test_attrs)

      # Then
      {test_cases, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(test_cases) == 1
      stable_case = hd(test_cases)
      assert stable_case.name == "testStableExample"
      assert stable_case.status == "success"
    end

    test "keeps test case as failure when final result is failure" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 2000,
        status: "failure",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "abc123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "FailingTestModule",
            status: "failure",
            duration: 2000,
            test_cases: [
              %{
                name: "testAlwaysFails",
                status: "failure",
                duration: 1000,
                repetitions: [
                  %{
                    repetition_number: 1,
                    name: "First Run",
                    status: "failure",
                    duration: 500
                  },
                  %{
                    repetition_number: 2,
                    name: "Retry 1",
                    status: "failure",
                    duration: 500
                  }
                ],
                failures: [
                  %{
                    message: "Always fails",
                    path: "/path/to/test.swift",
                    line_number: 20,
                    issue_type: "assertion"
                  }
                ]
              }
            ]
          }
        ]
      }

      # When
      {:ok, test} = Runs.create_test(test_attrs)

      # Then
      {test_cases, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(test_cases) == 1
      failed_case = hd(test_cases)
      assert failed_case.name == "testAlwaysFails"
      assert failed_case.status == "failure"
    end

    test "creates test without repetitions and keeps original status" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "abc123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "NormalTestModule",
            status: "success",
            duration: 1000,
            test_cases: [
              %{
                name: "testNormal",
                status: "success",
                duration: 500
              }
            ]
          }
        ]
      }

      # When
      {:ok, test} = Runs.create_test(test_attrs)

      # Then
      {test_cases, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(test_cases) == 1
      normal_case = hd(test_cases)
      assert normal_case.name == "testNormal"
      assert normal_case.status == "success"
    end
  end

  describe "list_test_case_runs/1 with flaky filter" do
    test "filters by is_flaky" do
      # Given
      {:ok, test} =
        RunsFixtures.test_fixture(
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "successTest", status: "success", duration: 100},
                %{name: "failureTest", status: "failure", duration: 200},
                %{
                  name: "flakyTest",
                  status: "success",
                  duration: 300,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 150},
                    %{repetition_number: 2, name: "Retry 1", status: "success", duration: 150}
                  ]
                }
              ]
            }
          ]
        )

      # When
      {test_cases, _meta} =
        Runs.list_test_case_runs(%{
          filters: [
            %{field: :test_run_id, op: :==, value: test.id},
            %{field: :is_flaky, op: :==, value: true}
          ]
        })

      # Then
      assert length(test_cases) == 1
      assert hd(test_cases).name == "flakyTest"
      assert hd(test_cases).is_flaky == true
    end
  end

  describe "cross-run flaky detection" do
    test "marks both runs as flaky when same test case on same commit has different results" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account_id = project.account_id
      commit_sha = "abc123def456"
      test_case_id = Ecto.UUID.generate()

      # First CI run: test case passes
      {:ok, first_test} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account_id,
          duration: 1000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: commit_sha,
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [
                %{
                  name: "testSomething",
                  status: "success",
                  duration: 250,
                  test_case_id: test_case_id
                }
              ]
            }
          ]
        })

      # Get the first test case run
      {first_test_case_runs, _} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: first_test.id}]
        })

      first_test_case_run = hd(first_test_case_runs)

      # First run should not be flaky initially
      assert first_test_case_run.is_flaky == false
      assert first_test_case_run.status == "success"

      # Second CI run: same test case on same commit fails (developer re-runs CI)
      {:ok, second_test} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account_id,
          duration: 1000,
          status: "failure",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: commit_sha,
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 500,
              test_cases: [
                %{
                  name: "testSomething",
                  status: "failure",
                  duration: 250,
                  test_case_id: test_case_id
                }
              ]
            }
          ]
        })

      # Force ClickHouse to merge and deduplicate rows
      RunsFixtures.optimize_test_case_runs()

      # Get the second test case run
      {second_test_case_runs, _} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: second_test.id}]
        })

      second_test_case_run = hd(second_test_case_runs)

      # Second run should be flaky (detected cross-run flakiness)
      assert second_test_case_run.is_flaky == true
      assert second_test_case_run.status == "failure"

      # First run should now also be marked as flaky (via ReplacingMergeTree update)
      {updated_first_runs, _} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: first_test.id}]
        })

      updated_first_run = hd(updated_first_runs)
      assert updated_first_run.is_flaky == true
      assert updated_first_run.status == "success"
    end

    test "marks all runs as flaky when multiple runs exist before a conflicting run" do
      # Scenario: Run A passes, Run B passes, Run C fails
      # All three should be marked as flaky
      project = ProjectsFixtures.project_fixture()
      commit_sha = "abc123def456"
      test_case_id = Ecto.UUID.generate()

      test_modules = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "testSomething", status: status, duration: 250, test_case_id: test_case_id}]
          }
        ]
      end

      {:ok, first_test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: commit_sha,
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200),
          test_modules: test_modules.("success")
        )

      {:ok, second_test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: commit_sha,
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          test_modules: test_modules.("success")
        )

      {:ok, third_test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: commit_sha,
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.utc_now(),
          test_modules: test_modules.("failure")
        )

      # Force ClickHouse to merge and deduplicate rows
      RunsFixtures.optimize_test_case_runs()

      # All three runs should be marked as flaky
      {third_runs, _} = Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: third_test.id}]})
      assert hd(third_runs).is_flaky == true

      {first_runs, _} = Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: first_test.id}]})
      assert hd(first_runs).is_flaky == true

      {second_runs, _} = Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: second_test.id}]})
      assert hd(second_runs).is_flaky == true
    end

    test "does not mark as flaky when same test case on different commits has different results" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account_id = project.account_id
      test_case_id = Ecto.UUID.generate()

      # First CI run: test case passes on commit A
      {:ok, first_test} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account_id,
          duration: 1000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "commit_a_123",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [
                %{
                  name: "testSomething",
                  status: "success",
                  duration: 250,
                  test_case_id: test_case_id
                }
              ]
            }
          ]
        })

      # Second CI run: same test case fails on different commit B
      {:ok, second_test} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account_id,
          duration: 1000,
          status: "failure",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "commit_b_456",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 500,
              test_cases: [
                %{
                  name: "testSomething",
                  status: "failure",
                  duration: 250,
                  test_case_id: test_case_id
                }
              ]
            }
          ]
        })

      # Get both test case runs
      {first_test_case_runs, _} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: first_test.id}]
        })

      {second_test_case_runs, _} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: second_test.id}]
        })

      # Neither should be marked as flaky (different commits)
      assert hd(first_test_case_runs).is_flaky == false
      assert hd(second_test_case_runs).is_flaky == false
    end

    test "does not mark as flaky for non-CI runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      account_id = project.account_id
      commit_sha = "same_commit_123"
      test_case_id = Ecto.UUID.generate()

      # First local run: test case passes
      {:ok, first_test} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account_id,
          duration: 1000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: commit_sha,
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          is_ci: false,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [
                %{
                  name: "testSomething",
                  status: "success",
                  duration: 250,
                  test_case_id: test_case_id
                }
              ]
            }
          ]
        })

      # Second local run: same test case fails on same commit
      {:ok, second_test} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account_id,
          duration: 1000,
          status: "failure",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: commit_sha,
          ran_at: NaiveDateTime.utc_now(),
          is_ci: false,
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 500,
              test_cases: [
                %{
                  name: "testSomething",
                  status: "failure",
                  duration: 250,
                  test_case_id: test_case_id
                }
              ]
            }
          ]
        })

      # Get both test case runs
      {first_test_case_runs, _} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: first_test.id}]
        })

      {second_test_case_runs, _} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: second_test.id}]
        })

      # Neither should be marked as flaky (not CI runs)
      assert hd(first_test_case_runs).is_flaky == false
      assert hd(second_test_case_runs).is_flaky == false
    end
  end

  describe "update_test_case/2" do
    test "marks a test case as flaky" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "testOne", status: "success", duration: 100}
              ]
            }
          ]
        )

      {[test_case], _meta} = Runs.list_test_cases(project.id, %{})
      assert test_case.is_flaky == false

      # When
      result = Runs.update_test_case(test_case.id, %{is_flaky: true}, project.id, %{type: :system, id: nil})

      # Then
      assert {:ok, updated_test_case} = result
      assert updated_test_case.is_flaky == true
      assert updated_test_case.id == test_case.id

      # Verify it persisted
      {:ok, fetched_test_case} = Runs.get_test_case_by_id(test_case.id)
      assert fetched_test_case.is_flaky == true
    end

    test "returns error when test case does not exist" do
      # Given
      project = ProjectsFixtures.project_fixture()
      non_existent_id = UUIDv7.generate()

      # When
      result = Runs.update_test_case(non_existent_id, %{is_flaky: true}, project.id, %{type: :system, id: nil})

      # Then
      assert result == {:error, :not_found}
    end

    test "keeps test case flaky if already flaky" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "testOne", status: "success", duration: 100}
              ]
            }
          ]
        )

      {[test_case], _meta} = Runs.list_test_cases(project.id, %{})

      # Mark as flaky first
      {:ok, _} = Runs.update_test_case(test_case.id, %{is_flaky: true}, project.id, %{type: :system, id: nil})

      # When - mark as flaky again
      result = Runs.update_test_case(test_case.id, %{is_flaky: true}, project.id, %{type: :system, id: nil})

      # Then
      assert {:ok, updated_test_case} = result
      assert updated_test_case.is_flaky == true
    end

    test "unmarks a test case as flaky" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "testOne", status: "success", duration: 100}
              ]
            }
          ]
        )

      {[test_case], _meta} = Runs.list_test_cases(project.id, %{})

      # Mark as flaky first
      {:ok, _} = Runs.update_test_case(test_case.id, %{is_flaky: true}, project.id, %{type: :system, id: nil})
      {:ok, flaky_test_case} = Runs.get_test_case_by_id(test_case.id)
      assert flaky_test_case.is_flaky == true

      # When
      result = Runs.update_test_case(test_case.id, %{is_flaky: false}, project.id, %{type: :system, id: nil})

      # Then
      assert {:ok, updated_test_case} = result
      assert updated_test_case.is_flaky == false
      assert updated_test_case.id == test_case.id

      # Verify it persisted
      {:ok, fetched_test_case} = Runs.get_test_case_by_id(test_case.id)
      assert fetched_test_case.is_flaky == false
    end

    test "returns error when unmarking test case that does not exist" do
      # Given
      project = ProjectsFixtures.project_fixture()
      non_existent_id = UUIDv7.generate()

      # When
      result = Runs.update_test_case(non_existent_id, %{is_flaky: false}, project.id, %{type: :system, id: nil})

      # Then
      assert result == {:error, :not_found}
    end

    test "keeps test case not flaky if already not flaky" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "testOne", status: "success", duration: 100}
              ]
            }
          ]
        )

      {[test_case], _meta} = Runs.list_test_cases(project.id, %{})
      assert test_case.is_flaky == false

      # When - unmark when already not flaky
      result = Runs.update_test_case(test_case.id, %{is_flaky: false}, project.id, %{type: :system, id: nil})

      # Then
      assert {:ok, updated_test_case} = result
      assert updated_test_case.is_flaky == false
    end
  end

  describe "update_test_case/4 quarantine" do
    test "marks a test case as quarantined" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "testOne", status: "success", duration: 100}
              ]
            }
          ]
        )

      {[test_case], _meta} = Runs.list_test_cases(project.id, %{})
      assert test_case.is_quarantined == false

      result = Runs.update_test_case(test_case.id, %{is_quarantined: true}, project.id, %{type: :system, id: nil})

      assert {:ok, updated_test_case} = result
      assert updated_test_case.is_quarantined == true
      assert updated_test_case.id == test_case.id

      {:ok, fetched_test_case} = Runs.get_test_case_by_id(test_case.id)
      assert fetched_test_case.is_quarantined == true
    end

    test "returns error when test case does not exist" do
      project = ProjectsFixtures.project_fixture()
      non_existent_id = UUIDv7.generate()

      result = Runs.update_test_case(non_existent_id, %{is_quarantined: true}, project.id, %{type: :system, id: nil})

      assert result == {:error, :not_found}
    end

    test "unquarantines a test case" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{name: "testOne", status: "success", duration: 100}
              ]
            }
          ]
        )

      {[test_case], _meta} = Runs.list_test_cases(project.id, %{})

      {:ok, _} = Runs.update_test_case(test_case.id, %{is_quarantined: true}, project.id, %{type: :system, id: nil})
      {:ok, quarantined_test_case} = Runs.get_test_case_by_id(test_case.id)
      assert quarantined_test_case.is_quarantined == true

      result = Runs.update_test_case(test_case.id, %{is_quarantined: false}, project.id, %{type: :system, id: nil})

      assert {:ok, updated_test_case} = result
      assert updated_test_case.is_quarantined == false
      assert updated_test_case.id == test_case.id

      {:ok, fetched_test_case} = Runs.get_test_case_by_id(test_case.id)
      assert fetched_test_case.is_quarantined == false
    end
  end

  describe "list_flaky_test_cases/2" do
    test "returns empty list when no flaky test cases exist" do
      project = ProjectsFixtures.project_fixture()

      {flaky_tests, meta} = Runs.list_flaky_test_cases(project.id, %{})

      assert flaky_tests == []
      assert meta.total_count == 0
      assert meta.total_pages == 0
    end

    test "returns flaky test cases for a project" do
      project = ProjectsFixtures.project_fixture()

      test_modules = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest", status: status, duration: 250}]
          }
        ]
      end

      {:ok, first_test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "abc123",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          test_modules: test_modules.("success")
        )

      {:ok, _second_test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "abc123",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.utc_now(),
          test_modules: test_modules.("failure")
        )

      # Get the actual test_case_id from the created test_case_run
      {[test_case_run | _], _} =
        Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: first_test.id}]})

      # Mark the test_case as flaky (simulating what the FlakyThresholdCheckWorker would do)
      {:ok, _} = Runs.update_test_case(test_case_run.test_case_id, %{is_flaky: true}, project.id, %{type: :system, id: nil})

      RunsFixtures.optimize_test_case_runs()

      {flaky_tests, meta} = Runs.list_flaky_test_cases(project.id, %{})

      assert length(flaky_tests) == 1
      assert meta.total_count == 1

      flaky_test = hd(flaky_tests)
      assert flaky_test.name == "flakyTest"
      assert flaky_test.module_name == "TestModule"
      assert flaky_test.flaky_runs_count == 2
    end

    test "supports pagination" do
      project = ProjectsFixtures.project_fixture()

      test_case_ids =
        for i <- 1..3 do
          test_modules = fn status ->
            [
              %{
                name: "TestModule",
                status: status,
                duration: 500,
                test_cases: [%{name: "flakyTest#{i}", status: status, duration: 250}]
              }
            ]
          end

          {:ok, first_test} =
            RunsFixtures.test_fixture(
              project_id: project.id,
              account_id: project.account_id,
              git_commit_sha: "commit#{i}",
              is_ci: true,
              status: "success",
              ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
              test_modules: test_modules.("success")
            )

          {:ok, _} =
            RunsFixtures.test_fixture(
              project_id: project.id,
              account_id: project.account_id,
              git_commit_sha: "commit#{i}",
              is_ci: true,
              status: "failure",
              ran_at: NaiveDateTime.utc_now(),
              test_modules: test_modules.("failure")
            )

          # Get the actual test_case_id from the created test_case_run
          {[test_case_run | _], _} =
            Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: first_test.id}]})

          test_case_run.test_case_id
        end

      # Mark all test_cases as flaky (simulating what the FlakyThresholdCheckWorker would do)
      for test_case_id <- test_case_ids do
        {:ok, _} = Runs.update_test_case(test_case_id, %{is_flaky: true}, project.id, %{type: :system, id: nil})
      end

      RunsFixtures.optimize_test_case_runs()

      {page1, meta1} = Runs.list_flaky_test_cases(project.id, %{page: 1, page_size: 2})
      assert length(page1) == 2
      assert meta1.total_count == 3
      assert meta1.total_pages == 2
      assert meta1.current_page == 1

      {page2, meta2} = Runs.list_flaky_test_cases(project.id, %{page: 2, page_size: 2})
      assert length(page2) == 1
      assert meta2.current_page == 2
    end

    test "supports search filtering by name" do
      project = ProjectsFixtures.project_fixture()

      test_case_ids =
        for {name, i} <- [{"loginTest", 1}, {"logoutTest", 2}, {"profileTest", 3}] do
          test_modules = fn status ->
            [
              %{
                name: "TestModule",
                status: status,
                duration: 500,
                test_cases: [%{name: name, status: status, duration: 250}]
              }
            ]
          end

          {:ok, first_test} =
            RunsFixtures.test_fixture(
              project_id: project.id,
              account_id: project.account_id,
              git_commit_sha: "commit#{i}",
              is_ci: true,
              status: "success",
              ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
              test_modules: test_modules.("success")
            )

          {:ok, _} =
            RunsFixtures.test_fixture(
              project_id: project.id,
              account_id: project.account_id,
              git_commit_sha: "commit#{i}",
              is_ci: true,
              status: "failure",
              ran_at: NaiveDateTime.utc_now(),
              test_modules: test_modules.("failure")
            )

          # Get the actual test_case_id from the created test_case_run
          {[test_case_run | _], _} =
            Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: first_test.id}]})

          test_case_run.test_case_id
        end

      # Mark all test_cases as flaky (simulating what the FlakyThresholdCheckWorker would do)
      for test_case_id <- test_case_ids do
        {:ok, _} = Runs.update_test_case(test_case_id, %{is_flaky: true}, project.id, %{type: :system, id: nil})
      end

      RunsFixtures.optimize_test_case_runs()

      {results, meta} =
        Runs.list_flaky_test_cases(project.id, %{
          filters: [%{field: :name, op: :ilike_and, value: "log"}]
        })

      assert length(results) == 2
      assert meta.total_count == 2
      names = Enum.map(results, & &1.name)
      assert "loginTest" in names
      assert "logoutTest" in names
    end

    test "supports ordering by name" do
      project = ProjectsFixtures.project_fixture()

      test_case_ids =
        for {name, i} <- [{"zebra", 1}, {"alpha", 2}, {"beta", 3}] do
          test_modules = fn status ->
            [
              %{
                name: "TestModule",
                status: status,
                duration: 500,
                test_cases: [%{name: name, status: status, duration: 250}]
              }
            ]
          end

          {:ok, first_test} =
            RunsFixtures.test_fixture(
              project_id: project.id,
              account_id: project.account_id,
              git_commit_sha: "commit#{i}",
              is_ci: true,
              status: "success",
              ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
              test_modules: test_modules.("success")
            )

          {:ok, _} =
            RunsFixtures.test_fixture(
              project_id: project.id,
              account_id: project.account_id,
              git_commit_sha: "commit#{i}",
              is_ci: true,
              status: "failure",
              ran_at: NaiveDateTime.utc_now(),
              test_modules: test_modules.("failure")
            )

          # Get the actual test_case_id from the created test_case_run
          {[test_case_run | _], _} =
            Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: first_test.id}]})

          test_case_run.test_case_id
        end

      # Mark all test_cases as flaky (simulating what the FlakyThresholdCheckWorker would do)
      for test_case_id <- test_case_ids do
        {:ok, _} = Runs.update_test_case(test_case_id, %{is_flaky: true}, project.id, %{type: :system, id: nil})
      end

      RunsFixtures.optimize_test_case_runs()

      {asc_results, _} =
        Runs.list_flaky_test_cases(project.id, %{order_by: [:name], order_directions: [:asc]})

      assert Enum.map(asc_results, & &1.name) == ["alpha", "beta", "zebra"]

      {desc_results, _} =
        Runs.list_flaky_test_cases(project.id, %{order_by: [:name], order_directions: [:desc]})

      assert Enum.map(desc_results, & &1.name) == ["zebra", "beta", "alpha"]
    end

    test "does not return test cases from other projects" do
      project1 = ProjectsFixtures.project_fixture()
      project2 = ProjectsFixtures.project_fixture()

      test_modules = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest", status: status, duration: 250}]
          }
        ]
      end

      {:ok, first_test} =
        RunsFixtures.test_fixture(
          project_id: project1.id,
          account_id: project1.account_id,
          git_commit_sha: "abc123",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          test_modules: test_modules.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project1.id,
          account_id: project1.account_id,
          git_commit_sha: "abc123",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.utc_now(),
          test_modules: test_modules.("failure")
        )

      # Get the actual test_case_id from the created test_case_run
      {[test_case_run | _], _} =
        Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: first_test.id}]})

      # Mark the test_case as flaky (simulating what the FlakyThresholdCheckWorker would do)
      {:ok, _} = Runs.update_test_case(test_case_run.test_case_id, %{is_flaky: true}, project.id, %{type: :system, id: nil})

      RunsFixtures.optimize_test_case_runs()

      {project1_results, _} = Runs.list_flaky_test_cases(project1.id, %{})
      assert length(project1_results) == 1

      {project2_results, _} = Runs.list_flaky_test_cases(project2.id, %{})
      assert project2_results == []
    end
  end

  describe "get_flaky_runs_groups_count_for_test_case/1" do
    test "returns 0 when no flaky runs exist" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          status: "success",
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [%{name: "testSomething", status: "success", duration: 250}]
            }
          ]
        )

      {[test_case], _} = Runs.list_test_cases(project.id, %{})

      count = Runs.get_flaky_runs_groups_count_for_test_case(test_case.id)
      assert count == 0
    end

    test "returns count of unique scheme + commit_sha groups" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()

      test_modules = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest", status: status, duration: 250, test_case_id: test_case_id}]
          }
        ]
      end

      # Create flaky runs on commit1
      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit1",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200),
          test_modules: test_modules.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit1",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          test_modules: test_modules.("failure")
        )

      # Create flaky runs on commit2
      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit2",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -1800),
          test_modules: test_modules.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit2",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.utc_now(),
          test_modules: test_modules.("failure")
        )

      RunsFixtures.optimize_test_case_runs()

      {[test_case], _} = Runs.list_test_cases(project.id, %{})
      count = Runs.get_flaky_runs_groups_count_for_test_case(test_case.id)

      # 2 groups: (default_scheme, commit1) and (default_scheme, commit2)
      assert count == 2
    end
  end

  describe "get_flaky_runs_groups_counts_for_test_cases/1" do
    test "returns empty map for empty list" do
      result = Runs.get_flaky_runs_groups_counts_for_test_cases([])
      assert result == %{}
    end

    test "returns empty map when no flaky runs exist for given test_case_ids" do
      project = ProjectsFixtures.project_fixture()

      {:ok, test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          status: "success",
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [%{name: "testSomething", status: "success", duration: 250}]
            }
          ]
        )

      {[test_case_run | _], _} =
        Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: test.id}]})

      result = Runs.get_flaky_runs_groups_counts_for_test_cases([test_case_run.test_case_id])
      assert result == %{}
    end

    test "returns correct counts for multiple test cases" do
      project = ProjectsFixtures.project_fixture()

      # Create flaky runs for test_case_1 on 2 commits
      test_modules_1 = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest1", status: status, duration: 250}]
          }
        ]
      end

      {:ok, test1} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit1",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200),
          test_modules: test_modules_1.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit1",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          test_modules: test_modules_1.("failure")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit2",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -1800),
          test_modules: test_modules_1.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit2",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -900),
          test_modules: test_modules_1.("failure")
        )

      # Create flaky runs for test_case_2 on 1 commit
      test_modules_2 = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest2", status: status, duration: 250}]
          }
        ]
      end

      {:ok, test2} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit3",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -600),
          test_modules: test_modules_2.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit3",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.utc_now(),
          test_modules: test_modules_2.("failure")
        )

      RunsFixtures.optimize_test_case_runs()

      {[test_case_run_1 | _], _} =
        Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: test1.id}]})

      {[test_case_run_2 | _], _} =
        Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: test2.id}]})

      result =
        Runs.get_flaky_runs_groups_counts_for_test_cases([
          test_case_run_1.test_case_id,
          test_case_run_2.test_case_id
        ])

      assert result[test_case_run_1.test_case_id] == 2
      assert result[test_case_run_2.test_case_id] == 1
    end

    test "only includes test_case_ids that have flaky runs" do
      project = ProjectsFixtures.project_fixture()

      # Create flaky test case
      test_modules_flaky = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest", status: status, duration: 250}]
          }
        ]
      end

      {:ok, flaky_test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit1",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          test_modules: test_modules_flaky.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit1",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.utc_now(),
          test_modules: test_modules_flaky.("failure")
        )

      # Create non-flaky test case (all runs succeed)
      {:ok, non_flaky_test} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "commit2",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.utc_now(),
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [%{name: "stableTest", status: "success", duration: 250}]
            }
          ]
        )

      RunsFixtures.optimize_test_case_runs()

      {[flaky_run | _], _} =
        Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: flaky_test.id}]})

      {[non_flaky_run | _], _} =
        Runs.list_test_case_runs(%{filters: [%{field: :test_run_id, op: :==, value: non_flaky_test.id}]})

      result =
        Runs.get_flaky_runs_groups_counts_for_test_cases([
          flaky_run.test_case_id,
          non_flaky_run.test_case_id
        ])

      assert Map.has_key?(result, flaky_run.test_case_id)
      refute Map.has_key?(result, non_flaky_run.test_case_id)
      assert result[flaky_run.test_case_id] == 1
    end
  end

  describe "list_flaky_runs_for_test_case/2" do
    test "returns empty list with meta when no flaky runs exist" do
      project = ProjectsFixtures.project_fixture()

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          status: "success",
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [%{name: "testSomething", status: "success", duration: 250}]
            }
          ]
        )

      {[test_case], _} = Runs.list_test_cases(project.id, %{})

      {groups, meta} = Runs.list_flaky_runs_for_test_case(test_case.id)

      assert groups == []
      assert meta.total_count == 0
      assert meta.total_pages == 0
    end

    test "returns flaky runs grouped by scheme and commit_sha" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()

      test_modules = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest", status: status, duration: 250, test_case_id: test_case_id}]
          }
        ]
      end

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "abc123",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          test_modules: test_modules.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "abc123",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.utc_now(),
          test_modules: test_modules.("failure")
        )

      RunsFixtures.optimize_test_case_runs()

      {[test_case], _} = Runs.list_test_cases(project.id, %{})
      {groups, meta} = Runs.list_flaky_runs_for_test_case(test_case.id)

      assert length(groups) == 1
      assert meta.total_count == 1

      group = hd(groups)
      assert group.git_commit_sha == "abc123"
      assert length(group.runs) == 2
      assert group.passed_count == 1
      assert group.failed_count == 1
    end

    test "supports pagination on groups" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()

      test_modules = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest", status: status, duration: 250, test_case_id: test_case_id}]
          }
        ]
      end

      # Create 3 groups (3 different commits)
      for i <- 1..3 do
        {:ok, _} =
          RunsFixtures.test_fixture(
            project_id: project.id,
            account_id: project.account_id,
            git_commit_sha: "commit#{i}",
            is_ci: true,
            status: "success",
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600 * i),
            test_modules: test_modules.("success")
          )

        {:ok, _} =
          RunsFixtures.test_fixture(
            project_id: project.id,
            account_id: project.account_id,
            git_commit_sha: "commit#{i}",
            is_ci: true,
            status: "failure",
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600 * i + 1800),
            test_modules: test_modules.("failure")
          )
      end

      RunsFixtures.optimize_test_case_runs()

      {[test_case], _} = Runs.list_test_cases(project.id, %{})

      {page1, meta1} = Runs.list_flaky_runs_for_test_case(test_case.id, %{page: 1, page_size: 2})
      assert length(page1) == 2
      assert meta1.total_count == 3
      assert meta1.total_pages == 2
      assert meta1.current_page == 1

      {page2, meta2} = Runs.list_flaky_runs_for_test_case(test_case.id, %{page: 2, page_size: 2})
      assert length(page2) == 1
      assert meta2.current_page == 2
    end

    test "orders groups by latest_ran_at descending" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()

      test_modules = fn status ->
        [
          %{
            name: "TestModule",
            status: status,
            duration: 500,
            test_cases: [%{name: "flakyTest", status: status, duration: 250, test_case_id: test_case_id}]
          }
        ]
      end

      # Create older group first
      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "older_commit",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -7200),
          test_modules: test_modules.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "older_commit",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          test_modules: test_modules.("failure")
        )

      # Create newer group
      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "newer_commit",
          is_ci: true,
          status: "success",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -1800),
          test_modules: test_modules.("success")
        )

      {:ok, _} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          git_commit_sha: "newer_commit",
          is_ci: true,
          status: "failure",
          ran_at: NaiveDateTime.utc_now(),
          test_modules: test_modules.("failure")
        )

      RunsFixtures.optimize_test_case_runs()

      {[test_case], _} = Runs.list_test_cases(project.id, %{})
      {groups, _} = Runs.list_flaky_runs_for_test_case(test_case.id)

      assert length(groups) == 2
      assert Enum.at(groups, 0).git_commit_sha == "newer_commit"
      assert Enum.at(groups, 1).git_commit_sha == "older_commit"
    end
  end

  describe "get_flaky_runs_for_test_run/1" do
    test "returns empty list when no flaky runs exist for the test run" do
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: project.account_id,
          status: "success",
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [%{name: "testSomething", status: "success", duration: 250}]
            }
          ]
        )

      result = Runs.get_flaky_runs_for_test_run(test_run.id)

      assert result == []
    end

    test "returns flaky runs grouped by test case" do
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 2000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "FlakyTestModule",
              status: "success",
              duration: 2000,
              test_cases: [
                %{
                  name: "testFlakyExample",
                  status: "success",
                  duration: 1000,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 400},
                    %{repetition_number: 2, name: "Retry 1", status: "success", duration: 600}
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      result = Runs.get_flaky_runs_for_test_run(test_run.id)

      assert length(result) == 1
      group = hd(result)
      assert is_binary(group.test_case_id)
      assert group.name == "testFlakyExample"
      assert group.module_name == "FlakyTestModule"
      assert length(group.runs) == 1
    end

    test "includes failures for each run" do
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 2000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "FlakyTestModule",
              status: "success",
              duration: 2000,
              test_cases: [
                %{
                  name: "testFlakyExample",
                  status: "success",
                  duration: 1000,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 400},
                    %{repetition_number: 2, name: "Retry 1", status: "success", duration: 600}
                  ],
                  failures: [
                    %{
                      message: "Assertion failed",
                      path: "/path/to/test.swift",
                      line_number: 42,
                      issue_type: "assertion_failure"
                    }
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      result = Runs.get_flaky_runs_for_test_run(test_run.id)

      assert length(result) == 1
      group = hd(result)
      run = hd(group.runs)
      assert length(run.failures) == 1
      failure = hd(run.failures)
      assert failure.message == "Assertion failed"
      assert failure.path == "/path/to/test.swift"
      assert failure.line_number == 42
    end

    test "includes repetitions for each run sorted by repetition_number" do
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 2000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "FlakyTestModule",
              status: "success",
              duration: 2000,
              test_cases: [
                %{
                  name: "testFlakyExample",
                  status: "success",
                  duration: 1000,
                  repetitions: [
                    %{repetition_number: 3, name: "Retry 2", status: "success", duration: 300},
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 400},
                    %{repetition_number: 2, name: "Retry 1", status: "failure", duration: 500}
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      result = Runs.get_flaky_runs_for_test_run(test_run.id)

      assert length(result) == 1
      group = hd(result)
      run = hd(group.runs)
      assert length(run.repetitions) == 3
      assert Enum.at(run.repetitions, 0).repetition_number == 1
      assert Enum.at(run.repetitions, 1).repetition_number == 2
      assert Enum.at(run.repetitions, 2).repetition_number == 3
    end

    test "calculates passed_count and failed_count from repetitions" do
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 2000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "FlakyTestModule",
              status: "success",
              duration: 2000,
              test_cases: [
                %{
                  name: "testFlakyExample",
                  status: "success",
                  duration: 1000,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 400},
                    %{repetition_number: 2, name: "Retry 1", status: "failure", duration: 500},
                    %{repetition_number: 3, name: "Retry 2", status: "success", duration: 300}
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      result = Runs.get_flaky_runs_for_test_run(test_run.id)

      assert length(result) == 1
      group = hd(result)
      assert group.passed_count == 1
      assert group.failed_count == 2
    end

    test "calculates passed_count and failed_count without repetitions" do
      project = ProjectsFixtures.project_fixture()

      # Create two test runs on the same commit to trigger cross-run flaky detection
      {:ok, _first_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 1000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [
                %{name: "testFlaky", status: "success", duration: 250}
              ]
            }
          ]
        })

      {:ok, second_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 1000,
          status: "failure",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 500,
              test_cases: [
                %{name: "testFlaky", status: "failure", duration: 250}
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      result = Runs.get_flaky_runs_for_test_run(second_run.id)

      assert length(result) == 1
      group = hd(result)
      assert group.passed_count == 0
      assert group.failed_count == 1
    end

    test "groups multiple test cases separately" do
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 2000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "FlakyTestModule",
              status: "success",
              duration: 2000,
              test_cases: [
                %{
                  name: "testFlakyOne",
                  status: "success",
                  duration: 1000,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 400},
                    %{repetition_number: 2, name: "Retry 1", status: "success", duration: 600}
                  ]
                },
                %{
                  name: "testFlakyTwo",
                  status: "success",
                  duration: 800,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 300},
                    %{repetition_number: 2, name: "Retry 1", status: "success", duration: 500}
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      result = Runs.get_flaky_runs_for_test_run(test_run.id)

      assert length(result) == 2
      names = Enum.map(result, & &1.name)
      assert "testFlakyOne" in names
      assert "testFlakyTwo" in names
    end

    test "sorts groups by latest_ran_at descending" do
      project = ProjectsFixtures.project_fixture()

      # Create a single test run with two flaky test cases
      {:ok, test_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 2000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 1000,
              test_cases: [
                %{
                  name: "testEarlier",
                  status: "success",
                  duration: 250,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 100},
                    %{repetition_number: 2, name: "Retry", status: "success", duration: 150}
                  ]
                },
                %{
                  name: "testLater",
                  status: "success",
                  duration: 250,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 100},
                    %{repetition_number: 2, name: "Retry", status: "success", duration: 150}
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      result = Runs.get_flaky_runs_for_test_run(test_run.id)

      # Both test cases should be returned
      assert length(result) == 2
      names = Enum.map(result, & &1.name)
      assert "testEarlier" in names
      assert "testLater" in names
    end

    test "only returns flaky runs from the specified test run" do
      project = ProjectsFixtures.project_fixture()

      # Create first test run with flaky test
      {:ok, first_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 1000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "abc123",
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [
                %{
                  name: "testFlaky",
                  status: "success",
                  duration: 250,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 100},
                    %{repetition_number: 2, name: "Retry", status: "success", duration: 150}
                  ]
                }
              ]
            }
          ]
        })

      # Create second test run with flaky test
      {:ok, second_run} =
        Runs.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          duration: 1000,
          status: "success",
          macos_version: "14.0",
          xcode_version: "15.0",
          git_branch: "main",
          git_commit_sha: "def456",
          ran_at: NaiveDateTime.utc_now(),
          is_ci: true,
          test_modules: [
            %{
              name: "TestModule",
              status: "success",
              duration: 500,
              test_cases: [
                %{
                  name: "testFlaky",
                  status: "success",
                  duration: 250,
                  repetitions: [
                    %{repetition_number: 1, name: "First Run", status: "failure", duration: 100},
                    %{repetition_number: 2, name: "Retry", status: "success", duration: 150}
                  ]
                }
              ]
            }
          ]
        })

      RunsFixtures.optimize_test_case_runs()

      # Query for first run - should only get flaky runs from first run
      result_first = Runs.get_flaky_runs_for_test_run(first_run.id)
      assert length(result_first) == 1
      assert length(hd(result_first).runs) == 1

      # Query for second run - should only get flaky runs from second run
      result_second = Runs.get_flaky_runs_for_test_run(second_run.id)
      assert length(result_second) == 1
      assert length(hd(result_second).runs) == 1
    end
  end

  describe "clear_stale_flaky_flags/0" do
    test "does not clear flaky flag when test case has recent flaky runs" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()

      test_case =
        RunsFixtures.test_case_fixture(
          id: test_case_id,
          project_id: project.id,
          is_flaky: true
        )

      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # Create a recent flaky run (within 14 days)
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        is_flaky: true,
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3, :day)
      )

      RunsFixtures.optimize_test_case_runs()

      {:ok, _count} = Runs.clear_stale_flaky_flags()

      {:ok, fetched_test_case} = Runs.get_test_case_by_id(test_case_id)
      assert fetched_test_case.is_flaky == true
    end

    test "clears flaky flag when test case has no recent flaky runs" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()

      test_case =
        RunsFixtures.test_case_fixture(
          id: test_case_id,
          project_id: project.id,
          is_flaky: true
        )

      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # Create an old flaky run (more than 14 days ago)
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        is_flaky: true,
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -20, :day)
      )

      RunsFixtures.optimize_test_case_runs()

      {:ok, count} = Runs.clear_stale_flaky_flags()

      assert count >= 1

      {:ok, fetched_test_case} = Runs.get_test_case_by_id(test_case_id)
      assert fetched_test_case.is_flaky == false
    end

    test "clears flaky flag when test case has no flaky runs at all" do
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()

      test_case =
        RunsFixtures.test_case_fixture(
          id: test_case_id,
          project_id: project.id,
          is_flaky: true
        )

      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # Create a non-flaky run
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        is_flaky: false,
        inserted_at: NaiveDateTime.utc_now()
      )

      RunsFixtures.optimize_test_case_runs()

      {:ok, count} = Runs.clear_stale_flaky_flags()

      assert count >= 1

      {:ok, fetched_test_case} = Runs.get_test_case_by_id(test_case_id)
      assert fetched_test_case.is_flaky == false
    end

    test "only clears stale flaky flags, preserving recent ones" do
      project = ProjectsFixtures.project_fixture()
      stale_test_case_id = Ecto.UUID.generate()
      recent_test_case_id = Ecto.UUID.generate()

      # Create a test case with stale flaky runs
      stale_test_case =
        RunsFixtures.test_case_fixture(
          id: stale_test_case_id,
          project_id: project.id,
          name: "staleTest",
          is_flaky: true
        )

      # Create a test case with recent flaky runs
      recent_test_case =
        RunsFixtures.test_case_fixture(
          id: recent_test_case_id,
          project_id: project.id,
          name: "recentTest",
          is_flaky: true
        )

      IngestRepo.insert_all(TestCase, [
        stale_test_case |> Map.from_struct() |> Map.delete(:__meta__),
        recent_test_case |> Map.from_struct() |> Map.delete(:__meta__)
      ])

      # Old flaky run for stale test case
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: stale_test_case_id,
        is_flaky: true,
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -20, :day)
      )

      # Recent flaky run for recent test case
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: recent_test_case_id,
        is_flaky: true,
        inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3, :day)
      )

      RunsFixtures.optimize_test_case_runs()

      {:ok, count} = Runs.clear_stale_flaky_flags()

      assert count >= 1

      {:ok, fetched_stale} = Runs.get_test_case_by_id(stale_test_case_id)
      assert fetched_stale.is_flaky == false

      {:ok, fetched_recent} = Runs.get_test_case_by_id(recent_test_case_id)
      assert fetched_recent.is_flaky == true
    end

    test "does not affect non-flaky test cases" do
      project = ProjectsFixtures.project_fixture()
      non_flaky_test_case_id = Ecto.UUID.generate()

      test_case =
        RunsFixtures.test_case_fixture(
          id: non_flaky_test_case_id,
          project_id: project.id,
          is_flaky: false
        )

      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      {:ok, _count} = Runs.clear_stale_flaky_flags()

      {:ok, fetched_test_case} = Runs.get_test_case_by_id(non_flaky_test_case_id)
      assert fetched_test_case.is_flaky == false
    end
  end

  describe "is_new detection for test case runs" do
    test "marks test_case_run as new when no prior CI run exists on default branch" do
      # Given - a project with default_branch "main"
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      # When - create a test run on a feature branch
      test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "feature-branch",
        git_commit_sha: "abc123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "NewTestModule",
            status: "success",
            duration: 1000,
            test_cases: [
              %{
                name: "testNewFeature",
                status: "success",
                duration: 500
              }
            ]
          }
        ]
      }

      {:ok, test} = Runs.create_test(test_attrs)

      # Then - the test case run should be marked as new
      {test_case_runs, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: test.id}]
        })

      assert length(test_case_runs) == 1
      test_case_run = hd(test_case_runs)
      assert test_case_run.is_new == true
    end

    test "marks test_case_run as not new when prior CI run exists on default branch" do
      # Given - a project with a test case that has been run on main
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      # First, create a CI test run on main (default branch)
      main_test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "main123",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
        is_ci: true,
        test_modules: [
          %{
            name: "ExistingTestModule",
            status: "success",
            duration: 1000,
            test_cases: [
              %{
                name: "testExistingFeature",
                status: "success",
                duration: 500
              }
            ]
          }
        ]
      }

      {:ok, _main_test} = Runs.create_test(main_test_attrs)

      # When - create another test run on a feature branch with the same test case
      feature_test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "feature-branch",
        git_commit_sha: "feature123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "ExistingTestModule",
            status: "success",
            duration: 1000,
            test_cases: [
              %{
                name: "testExistingFeature",
                status: "success",
                duration: 500
              }
            ]
          }
        ]
      }

      {:ok, feature_test} = Runs.create_test(feature_test_attrs)

      # Then - the test case run should NOT be marked as new
      {test_case_runs, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: feature_test.id}]
        })

      assert length(test_case_runs) == 1
      test_case_run = hd(test_case_runs)
      assert test_case_run.is_new == false
    end

    test "non-CI runs on default branch do not affect is_new detection" do
      # Given - a project with a non-CI test run on main
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      # Create a non-CI test run on main
      non_ci_main_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "main123",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
        is_ci: false,
        test_modules: [
          %{
            name: "LocalTestModule",
            status: "success",
            duration: 1000,
            test_cases: [
              %{
                name: "testLocalOnly",
                status: "success",
                duration: 500
              }
            ]
          }
        ]
      }

      {:ok, _non_ci_test} = Runs.create_test(non_ci_main_attrs)

      # When - create a CI test run on feature branch with the same test case
      ci_feature_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "feature-branch",
        git_commit_sha: "feature123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "LocalTestModule",
            status: "success",
            duration: 1000,
            test_cases: [
              %{
                name: "testLocalOnly",
                status: "success",
                duration: 500
              }
            ]
          }
        ]
      }

      {:ok, ci_test} = Runs.create_test(ci_feature_attrs)

      # Then - the test case run should still be marked as new (non-CI runs don't count)
      {test_case_runs, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: ci_test.id}]
        })

      assert length(test_case_runs) == 1
      test_case_run = hd(test_case_runs)
      assert test_case_run.is_new == true
    end

    test "mixed new and existing test cases in same run" do
      # Given - a project with one test case already on main
      project = ProjectsFixtures.project_fixture()
      account = AccountsFixtures.user_fixture(preload: [:account]).account

      # Create a CI test run on main with one test case
      main_test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 1000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "main",
        git_commit_sha: "main123",
        ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600),
        is_ci: true,
        test_modules: [
          %{
            name: "MixedTestModule",
            status: "success",
            duration: 1000,
            test_cases: [
              %{
                name: "testExisting",
                status: "success",
                duration: 500
              }
            ]
          }
        ]
      }

      {:ok, _main_test} = Runs.create_test(main_test_attrs)

      # When - create a test run on feature branch with both existing and new test cases
      feature_test_attrs = %{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 2000,
        status: "success",
        model_identifier: "Mac15,6",
        macos_version: "14.0",
        xcode_version: "15.0",
        git_branch: "feature-branch",
        git_commit_sha: "feature123",
        ran_at: NaiveDateTime.utc_now(),
        is_ci: true,
        test_modules: [
          %{
            name: "MixedTestModule",
            status: "success",
            duration: 2000,
            test_cases: [
              %{
                name: "testExisting",
                status: "success",
                duration: 500
              },
              %{
                name: "testBrandNew",
                status: "success",
                duration: 500
              }
            ]
          }
        ]
      }

      {:ok, feature_test} = Runs.create_test(feature_test_attrs)

      # Then - one should be new, one should not
      {test_case_runs, _meta} =
        Runs.list_test_case_runs(%{
          filters: [%{field: :test_run_id, op: :==, value: feature_test.id}]
        })

      assert length(test_case_runs) == 2

      existing_run = Enum.find(test_case_runs, &(&1.name == "testExisting"))
      new_run = Enum.find(test_case_runs, &(&1.name == "testBrandNew"))

      assert existing_run.is_new == false
      assert new_run.is_new == true
    end
  end

  describe "list_test_case_events/2" do
    test "lists events for a test case ordered by inserted_at desc" do
      # Given
      project = ProjectsFixtures.project_fixture()
      user = AccountsFixtures.user_fixture(preload: [:account])
      test_case_id = Ecto.UUID.generate()
      event1_id = Ecto.UUID.generate()
      event2_id = Ecto.UUID.generate()
      now = NaiveDateTime.utc_now()

      IngestRepo.insert_all(TestCaseEvent, [
        %{
          id: event1_id,
          test_case_id: test_case_id,
          project_id: project.id,
          event_type: "marked_flaky",
          actor_type: "user",
          actor_id: user.account.id,
          metadata: "{}",
          inserted_at: now
        },
        %{
          id: event2_id,
          test_case_id: test_case_id,
          project_id: project.id,
          event_type: "quarantined",
          actor_type: "system",
          actor_id: nil,
          metadata: "{}",
          inserted_at: now
        }
      ])

      # When
      {events, meta} = Runs.list_test_case_events(test_case_id)

      # Then
      assert length(events) == 2
      assert meta.total_count == 2
      event_ids = Enum.map(events, & &1.id)
      assert event1_id in event_ids
      assert event2_id in event_ids
    end

    test "paginates events correctly" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = Ecto.UUID.generate()
      now = NaiveDateTime.utc_now()

      events =
        for _ <- 1..5 do
          %{
            id: Ecto.UUID.generate(),
            test_case_id: test_case_id,
            project_id: project.id,
            event_type: "marked_flaky",
            actor_type: "system",
            actor_id: nil,
            metadata: "{}",
            inserted_at: now
          }
        end

      IngestRepo.insert_all(TestCaseEvent, events)

      # When
      {events, meta} = Runs.list_test_case_events(test_case_id, %{page: 1, page_size: 2})

      # Then
      assert length(events) == 2
      assert meta.total_count == 5
      assert meta.total_pages == 3
      assert meta.current_page == 1
    end

    test "loads actor" do
      # Given
      project = ProjectsFixtures.project_fixture()
      user = AccountsFixtures.user_fixture(preload: [:account])
      test_case_id = Ecto.UUID.generate()
      now = NaiveDateTime.utc_now()

      IngestRepo.insert_all(TestCaseEvent, [
        %{
          id: Ecto.UUID.generate(),
          test_case_id: test_case_id,
          project_id: project.id,
          event_type: "marked_flaky",
          actor_type: "user",
          actor_id: user.account.id,
          metadata: "{}",
          inserted_at: now
        }
      ])

      # When
      {[event], _meta} = Runs.list_test_case_events(test_case_id)

      # Then
      assert event.actor.id == user.account.id
      assert event.actor.name == user.account.name
    end
  end

  describe "update_test_case/4 with event creation" do
    test "creates marked_flaky event when is_flaky changes from false to true" do
      # Given
      project = ProjectsFixtures.project_fixture()
      user = AccountsFixtures.user_fixture(preload: [:account])
      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false)
      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # When
      {:ok, _updated} =
        Runs.update_test_case(
          test_case.id,
          %{is_flaky: true},
          project.id,
          %{type: :user, id: user.account.id}
        )

      # Then
      {events, _meta} = Runs.list_test_case_events(test_case.id)
      assert length(events) == 1
      assert hd(events).event_type == "marked_flaky"
      assert hd(events).actor_id == user.account.id
    end

    test "creates unmarked_flaky event when is_flaky changes from true to false" do
      # Given
      project = ProjectsFixtures.project_fixture()
      user = AccountsFixtures.user_fixture(preload: [:account])
      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: true)
      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # When
      {:ok, _updated} =
        Runs.update_test_case(
          test_case.id,
          %{is_flaky: false},
          project.id,
          %{type: :user, id: user.account.id}
        )

      # Then
      {events, _meta} = Runs.list_test_case_events(test_case.id)
      assert length(events) == 1
      assert hd(events).event_type == "unmarked_flaky"
    end

    test "creates quarantined event when is_quarantined changes from false to true" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_quarantined: false)
      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # When
      {:ok, _updated} =
        Runs.update_test_case(
          test_case.id,
          %{is_quarantined: true},
          project.id,
          %{type: :system, id: nil}
        )

      # Then
      {events, _meta} = Runs.list_test_case_events(test_case.id)
      assert length(events) == 1
      assert hd(events).event_type == "quarantined"
      assert hd(events).actor_type == "system"
    end

    test "creates multiple events when both is_flaky and is_quarantined change" do
      # Given
      project = ProjectsFixtures.project_fixture()
      user = AccountsFixtures.user_fixture(preload: [:account])
      test_case = RunsFixtures.test_case_fixture(project_id: project.id, is_flaky: false, is_quarantined: false)
      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # When
      {:ok, _updated} =
        Runs.update_test_case(
          test_case.id,
          %{is_flaky: true, is_quarantined: true},
          project.id,
          %{type: :user, id: user.account.id}
        )

      # Then
      {events, _meta} = Runs.list_test_case_events(test_case.id)
      assert length(events) == 2
      event_types = Enum.map(events, & &1.event_type)
      assert "marked_flaky" in event_types
      assert "quarantined" in event_types
    end

  end
end
