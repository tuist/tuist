defmodule Tuist.RunsTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Runs
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
end
