defmodule Tuist.Tests.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.IngestRepo
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRun
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "get_test_run_metrics/1" do
    test "returns correct metrics when test run has test cases" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testTwo",
          status: 1,
          is_flaky: false,
          duration: 200,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testThree",
          status: 0,
          is_flaky: false,
          duration: 300,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        }
      ])

      # When
      got = Analytics.get_test_run_metrics(test_run.id)

      # Then
      assert got.total_count == 3
      assert got.failed_count == 1
      assert got.flaky_count == 0
      assert got.avg_duration == 200
    end

    test "returns correct flaky_count when test run has flaky test cases" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testSuccess",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testFlaky",
          status: 0,
          is_flaky: true,
          duration: 200,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testFailure",
          status: 1,
          is_flaky: false,
          duration: 300,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testAnotherFlaky",
          status: 0,
          is_flaky: true,
          duration: 150,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        }
      ])

      # When
      got = Analytics.get_test_run_metrics(test_run.id)

      # Then
      assert got.total_count == 4
      assert got.failed_count == 1
      assert got.flaky_count == 2
      assert got.avg_duration == 188
    end

    test "returns zeros when test run has no test cases" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      # When - no test case runs inserted
      got = Analytics.get_test_run_metrics(test_run.id)

      # Then - should return zeros, not nil
      assert got.total_count == 0
      assert got.failed_count == 0
      assert got.flaky_count == 0
      assert got.avg_duration == 0
    end
  end

  describe "test_runs_metrics/2" do
    test "returns metrics and command event data for test runs" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create test runs
      {:ok, test_run_one} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      {:ok, test_run_two} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "def456",
          status: "failure",
          is_flaky: false,
          scheme: "AnotherScheme",
          duration: 2000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: false,
          ran_at: ~N[2024-04-30 11:00:00.000000],
          test_modules: []
        })

      # Create test case runs for both test runs
      module_run_id_one = UUIDv7.generate()
      module_run_id_two = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_one.id,
          test_module_run_id: module_run_id_one,
          project_id: project.id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          is_flaky: false,
          duration: 50,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_two.id,
          test_module_run_id: module_run_id_two,
          project_id: project.id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testSuccess",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 11:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_two.id,
          test_module_run_id: module_run_id_two,
          project_id: project.id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testFailure",
          status: 1,
          is_flaky: false,
          duration: 200,
          inserted_at: ~N[2024-04-30 11:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_two.id,
          test_module_run_id: module_run_id_two,
          project_id: project.id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testAnother",
          status: 0,
          is_flaky: false,
          duration: 150,
          inserted_at: ~N[2024-04-30 11:00:00.000000]
        }
      ])

      # Create command events linked to test runs
      _command_event_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          test_run_id: test_run_one.id,
          cacheable_targets: ["A", "B", "C"],
          local_cache_target_hits: ["A"],
          remote_cache_target_hits: ["B"],
          test_targets: ["TestA", "TestB"],
          local_test_target_hits: ["TestA"],
          remote_test_target_hits: [],
          duration: 5000,
          created_at: ~N[2024-04-30 10:00:00.000000]
        )

      _command_event_two =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          name: "test",
          subcommand: "test-without-building",
          test_run_id: test_run_two.id,
          cacheable_targets: ["D", "E", "F", "G"],
          local_cache_target_hits: [],
          remote_cache_target_hits: ["E", "F"],
          test_targets: ["TestC", "TestD", "TestE"],
          local_test_target_hits: ["TestC"],
          remote_test_target_hits: ["TestD"],
          duration: 3000,
          created_at: ~N[2024-04-30 11:00:00.000000]
        )

      # When
      got = Analytics.test_runs_metrics(project.id, [test_run_one, test_run_two])

      # Then
      assert length(got) == 2

      # Find results for each test run
      result_one = Enum.find(got, &(&1.test_run_id == test_run_one.id))
      result_two = Enum.find(got, &(&1.test_run_id == test_run_two.id))

      # Verify test_run_one metrics (1 test case run)
      # Cache: 3 cacheable targets, 2 hits (A local, B remote) = 66%
      # Skipped: 1 local test target hit (TestA) = 1 skipped
      # Ran: 1 total - 1 skipped = 0 ran
      assert result_one.test_run_id == test_run_one.id
      assert result_one.total_tests == 1
      assert result_one.cache_hit_rate == "66 %"
      assert result_one.skipped_tests == 1
      assert result_one.ran_tests == 0

      # Verify test_run_two metrics (3 test case runs: 2 success, 1 failure)
      # Cache: 4 cacheable targets, 2 hits (E, F remote) = 50%
      # Skipped: 2 test target hits (TestC local, TestD remote) = 2 skipped
      # Ran: 3 total - 2 skipped = 1 ran
      assert result_two.test_run_id == test_run_two.id
      assert result_two.total_tests == 3
      assert result_two.cache_hit_rate == "50 %"
      assert result_two.skipped_tests == 2
      assert result_two.ran_tests == 1
    end

    test "handles test runs without command events" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      # Create test case runs but no command event
      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: UUIDv7.generate(),
          project_id: project.id,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        }
      ])

      # When
      got = Analytics.test_runs_metrics(project.id, [test_run])

      # Then
      assert length(got) == 1
      result = List.first(got)

      # Without command event, no cache targets or test target hits
      # Cache: 0 cacheable targets = 0%
      # Skipped: 0 test target hits = 0 skipped
      # Ran: 1 total - 0 skipped = 1 ran
      assert result.test_run_id == test_run.id
      assert result.total_tests == 1
      assert result.cache_hit_rate == "0 %"
      assert result.skipped_tests == 0
      assert result.ran_tests == 1
    end
  end

  describe "test_case_run_analytics/2" do
    test "returns test case run count analytics for the last three days" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testTwo",
          status: 0,
          is_flaky: false,
          duration: 200,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testThree",
          status: 0,
          is_flaky: false,
          duration: 300,
          inserted_at: ~N[2024-04-29 10:00:00.000000]
        }
      ])

      # When
      got =
        Analytics.test_case_run_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day)
        )

      # Then
      assert got.count == 3
      assert got.values == [0, 1, 2]
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
    end

    test "filters by is_ci when specified" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      {:ok, ci_test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      {:ok, local_test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "def456",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: false,
          ran_at: ~N[2024-04-30 11:00:00.000000],
          test_modules: []
        })

      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: ci_test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: local_test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: false,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testTwo",
          status: 0,
          is_flaky: false,
          duration: 200,
          inserted_at: ~N[2024-04-30 11:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: local_test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: false,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testThree",
          status: 0,
          is_flaky: false,
          duration: 300,
          inserted_at: ~N[2024-04-30 11:00:00.000000]
        }
      ])

      # When - filter by CI only
      got =
        Analytics.test_case_run_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          is_ci: true
        )

      # Then
      assert got.count == 1
    end

    test "filters failed test case runs" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testTwo",
          status: 1,
          is_flaky: false,
          duration: 200,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testThree",
          status: 1,
          is_flaky: false,
          duration: 300,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        }
      ])

      # When - filter by failed status
      got =
        Analytics.test_case_run_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          status: "failure"
        )

      # Then
      assert got.count == 2
    end

    test "returns zero when no test case runs exist" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        Analytics.test_case_run_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day)
        )

      # Then
      assert got.count == 0
      assert got.trend == 0
    end
  end

  describe "test_case_run_duration_analytics/2" do
    test "returns duration analytics with percentiles" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testTwo",
          status: 0,
          is_flaky: false,
          duration: 200,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testThree",
          status: 0,
          is_flaky: false,
          duration: 300,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        }
      ])

      # When
      got =
        Analytics.test_case_run_duration_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day)
        )

      # Then
      assert got.total_average_duration == 200.0
      assert got.p50
      assert got.p90
      assert got.p99
      # Verify percentile time series are returned
      assert got.dates
      assert got.values
      assert got.p50_values
      assert got.p90_values
      assert got.p99_values
      assert length(got.dates) == length(got.p50_values)
      assert length(got.dates) == length(got.p90_values)
      assert length(got.dates) == length(got.p99_values)
    end

    test "returns zero when no test case runs exist" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        Analytics.test_case_run_duration_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day)
        )

      # Then
      assert got.total_average_duration == 0
      assert got.p50 == 0
      assert got.p90 == 0
      assert got.p99 == 0
      assert got.trend == 0
      # Verify percentile time series are filled with zeros (one for each day in the range)
      assert Enum.all?(got.p50_values, &(&1 == 0))
      assert Enum.all?(got.p90_values, &(&1 == 0))
      assert Enum.all?(got.p99_values, &(&1 == 0))
    end

    test "filters by is_ci when specified" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      {:ok, ci_test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      {:ok, local_test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "def456",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: false,
          ran_at: ~N[2024-04-30 11:00:00.000000],
          test_modules: []
        })

      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: ci_test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: true,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testOne",
          status: 0,
          is_flaky: false,
          duration: 500,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: local_test_run.id,
          test_module_run_id: module_run_id,
          project_id: project.id,
          is_ci: false,
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testTwo",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 11:00:00.000000]
        }
      ])

      # When - filter by CI only
      got =
        Analytics.test_case_run_duration_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          is_ci: true
        )

      # Then - only CI test case run has 500ms duration
      assert got.total_average_duration == 500.0
    end
  end

  describe "test_run_duration_analytics/2" do
    test "returns duration analytics with percentiles" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      {:ok, _test_run_1} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 07:00:00.000000],
          test_modules: []
        })

      {:ok, _test_run_2} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "def456",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 2000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 08:00:00.000000],
          test_modules: []
        })

      {:ok, _test_run_3} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "ghi789",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 3000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 09:00:00.000000],
          test_modules: []
        })

      # When
      got =
        Analytics.test_run_duration_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day)
        )

      # Then
      assert got.total_average_duration == 2000.0
      assert got.p50
      assert got.p90
      assert got.p99
      assert got.dates
      assert got.values
      assert got.p50_values
      assert got.p90_values
      assert got.p99_values
      assert length(got.dates) == length(got.p50_values)
      assert length(got.dates) == length(got.p90_values)
      assert length(got.dates) == length(got.p99_values)
    end

    test "returns zero when no test runs exist" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        Analytics.test_run_duration_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day)
        )

      # Then
      assert got.total_average_duration == 0.0
      assert got.p50 == 0.0
      assert got.p90 == 0.0
      assert got.p99 == 0.0
      assert got.dates
      assert got.values
      assert got.p50_values
      assert got.p90_values
      assert got.p99_values
    end

    test "filters by is_ci" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      {:ok, _ci_test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "abc123",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 5000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: true,
          ran_at: ~N[2024-04-30 10:00:00.000000],
          test_modules: []
        })

      {:ok, _local_test_run} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: project.account_id,
          git_ref: "refs/heads/main",
          git_commit_sha: "def456",
          status: "success",
          is_flaky: false,
          scheme: "TestScheme",
          duration: 1000,
          macos_version: "14.0",
          xcode_version: "15.0",
          is_ci: false,
          ran_at: ~N[2024-04-30 11:00:00.000000],
          test_modules: []
        })

      # When - filter by CI only
      got =
        Analytics.test_run_duration_analytics(
          project.id,
          start_datetime: DateTime.add(DateTime.utc_now(), -2, :day),
          is_ci: true
        )

      # Then - only CI test run has 5000ms duration
      assert got.total_average_duration == 5000.0
    end
  end

  describe "test_run_average_duration_analytics/2" do
    test "returns the current average and trend without percentile data" do
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_fixture(
        project_id: project.id,
        duration: 1000,
        ran_at: ~N[2024-04-28 12:00:00]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        duration: 1000,
        ran_at: ~N[2024-04-29 12:00:00]
      )

      RunsFixtures.test_fixture(
        project_id: project.id,
        duration: 3000,
        ran_at: ~N[2024-04-30 09:00:00]
      )

      got =
        Analytics.test_run_average_duration_analytics(
          project.id,
          start_datetime: ~U[2024-04-29 10:20:30Z]
        )

      assert got == %{total_average_duration: 2000.0, trend: 100.0}
    end
  end

  describe "test_case_reliability_by_id/3" do
    test "returns reliability percentage for test case runs on default branch" do
      # Given
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      test_case_id = UUIDv7.generate()
      test_run_id = UUIDv7.generate()
      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "main",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "main",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:01:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "main",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 1,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:02:00.000000]
        }
      ])

      # When
      got = Analytics.test_case_reliability_by_id(project.id, test_case_id, "main")

      # Then - 2 successes out of 3 runs = 66.7%
      assert got == 66.7
    end

    test "ignores runs belonging to another project" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        git_branch: "main",
        status: 0
      )

      RunsFixtures.test_case_run_fixture(
        project_id: other_project.id,
        test_case_id: test_case_id,
        git_branch: "main",
        status: 1
      )

      # When
      got = Analytics.test_case_reliability_by_id(project.id, test_case_id, "main")

      # Then
      assert got == 100.0
    end

    test "returns 100% when all runs on default branch are successful" do
      # Given
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      test_case_id = UUIDv7.generate()
      test_run_id = UUIDv7.generate()
      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "main",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "main",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:01:00.000000]
        }
      ])

      # When
      got = Analytics.test_case_reliability_by_id(project.id, test_case_id, "main")

      # Then
      assert got == 100.0
    end

    test "falls back to all branches when no runs exist on default branch" do
      # Given
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      test_case_id = UUIDv7.generate()
      test_run_id = UUIDv7.generate()
      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "feature-branch",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "another-branch",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:01:00.000000]
        }
      ])

      # When - no runs on "main" branch, should fall back to all branches
      got = Analytics.test_case_reliability_by_id(project.id, test_case_id, "main")

      # Then - 2 successes out of 2 runs = 100%
      assert got == 100.0
    end

    test "falls back to all branches and calculates correct reliability when some failed" do
      # Given
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      test_case_id = UUIDv7.generate()
      test_run_id = UUIDv7.generate()
      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "feature-branch",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "another-branch",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 1,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:01:00.000000]
        }
      ])

      # When - no runs on "main" branch, should fall back to all branches
      got = Analytics.test_case_reliability_by_id(project.id, test_case_id, "main")

      # Then - 1 success out of 2 runs = 50%
      assert got == 50.0
    end

    test "returns nil when no runs exist at all" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      # When
      got = Analytics.test_case_reliability_by_id(project.id, test_case_id, "main")

      # Then
      assert got == nil
    end

    test "prioritizes default branch runs over other branches" do
      # Given
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      test_case_id = UUIDv7.generate()
      test_run_id = UUIDv7.generate()
      module_run_id = UUIDv7.generate()

      IngestRepo.insert_all(TestCaseRun, [
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "main",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 1,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:00:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "feature-branch",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:01:00.000000]
        },
        %{
          id: UUIDv7.generate(),
          test_run_id: test_run_id,
          test_module_run_id: module_run_id,
          test_case_id: test_case_id,
          project_id: project.id,
          git_branch: "feature-branch",
          module_name: "MyTests",
          suite_name: "TestSuite",
          name: "testExample",
          status: 0,
          is_flaky: false,
          duration: 100,
          inserted_at: ~N[2024-04-30 10:02:00.000000]
        }
      ])

      # When - should use only "main" branch runs
      got = Analytics.test_case_reliability_by_id(project.id, test_case_id, "main")

      # Then - 0 successes out of 1 run on main = 0%
      assert got == 0.0
    end

    test "only counts runs within the given period" do
      # Given - the ingestion timestamps are deliberately the inverse of the run
      # timestamps, so bounding the wrong column would flip the result to 0.0.
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        git_branch: "main",
        status: 0,
        ran_at: ~N[2024-04-30 10:00:00.000000],
        inserted_at: ~N[2024-05-20 10:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        git_branch: "main",
        status: 1,
        ran_at: ~N[2024-04-10 10:00:00.000000],
        inserted_at: ~N[2024-04-30 10:00:00.000000]
      )

      # When
      got =
        Analytics.test_case_reliability_by_id(project.id, test_case_id, "main",
          start_datetime: ~U[2024-04-29 00:00:00Z],
          end_datetime: ~U[2024-05-01 00:00:00Z]
        )

      # Then - only the run that executed inside the period counts
      assert got == 100.0
    end

    test "falls back to all branches within the given period" do
      # Given
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        git_branch: "main",
        status: 0,
        ran_at: ~N[2024-04-10 10:00:00.000000],
        inserted_at: ~N[2024-04-30 10:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        git_branch: "feature-branch",
        status: 1,
        ran_at: ~N[2024-04-30 10:00:00.000000],
        inserted_at: ~N[2024-05-20 10:00:00.000000]
      )

      # When - the default branch has no runs inside the period
      got =
        Analytics.test_case_reliability_by_id(project.id, test_case_id, "main",
          start_datetime: ~U[2024-04-29 00:00:00Z],
          end_datetime: ~U[2024-05-01 00:00:00Z]
        )

      # Then
      assert got == 0.0
    end

    test "returns nil when no runs fall within the given period" do
      # Given
      project = ProjectsFixtures.project_fixture(default_branch: "main")
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        git_branch: "main",
        status: 0,
        ran_at: ~N[2024-04-10 10:00:00.000000],
        inserted_at: ~N[2024-04-30 10:00:00.000000]
      )

      # When
      got =
        Analytics.test_case_reliability_by_id(project.id, test_case_id, "main",
          start_datetime: ~U[2024-04-29 00:00:00Z],
          end_datetime: ~U[2024-05-01 00:00:00Z]
        )

      # Then - ingested inside the period, but it did not run inside it
      assert got == nil
    end
  end

  describe "test_case_analytics_by_id/2" do
    test "aggregates only runs belonging to the project" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 0,
        duration: 100
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 1,
        duration: 300
      )

      RunsFixtures.test_case_run_fixture(
        project_id: other_project.id,
        test_case_id: test_case_id,
        status: 1,
        duration: 1000
      )

      # When
      got = Analytics.test_case_analytics_by_id(project.id, test_case_id)

      # Then
      assert got == %{
               total_count: 2,
               failed_count: 1,
               flaky_count: 0,
               outcome_counts: %{successful: 1, failed: 1, flaky: 0, quarantined: 0, skipped: 0},
               avg_duration: 200,
               p50_duration: 200,
               p90_duration: 280,
               p99_duration: 298
             }
    end

    test "counts the flaky runs beside the failed ones" do
      # Given - the runs widget reports both, and a flaky run is not a failed one
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for {status, is_flaky} <- [{0, false}, {1, false}, {0, true}, {0, true}] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: status,
          is_flaky: is_flaky,
          duration: 100
        )
      end

      # When
      got = Analytics.test_case_analytics_by_id(project.id, test_case_id)

      # Then
      assert got.total_count == 4
      assert got.failed_count == 1
      assert got.flaky_count == 2
    end

    test "counts each outcome the way the stacked bar segments it" do
      # Given - one run that is failed and flaky at once, and one plainly failed
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 1,
        is_flaky: true,
        duration: 100
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 1,
        duration: 100
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 1,
        is_quarantined: true,
        duration: 100
      )

      # When
      got = Analytics.test_case_analytics_by_id(project.id, test_case_id)

      # Then - the totals answer "how many runs failed at all", the outcome
      # counts answer "which segment of the bar is this run in"
      assert got.failed_count == 3
      assert got.flaky_count == 1

      assert got.outcome_counts == %{
               successful: 0,
               failed: 1,
               flaky: 1,
               quarantined: 1,
               skipped: 0
             }
    end

    test "only aggregates runs within the given period" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 0,
        duration: 100,
        ran_at: ~N[2024-04-30 10:00:00.000000],
        inserted_at: ~N[2024-05-20 10:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 1,
        duration: 300,
        ran_at: ~N[2024-04-30 10:01:00.000000],
        inserted_at: ~N[2024-05-20 10:01:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 1,
        duration: 5000,
        ran_at: ~N[2024-04-10 10:00:00.000000],
        inserted_at: ~N[2024-04-30 10:00:00.000000]
      )

      # When
      got =
        Analytics.test_case_analytics_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-29 00:00:00Z],
          end_datetime: ~U[2024-05-01 00:00:00Z]
        )

      # Then - the run from outside the period is excluded from every aggregate
      assert got == %{
               total_count: 2,
               failed_count: 1,
               flaky_count: 0,
               outcome_counts: %{successful: 1, failed: 1, flaky: 0, quarantined: 0, skipped: 0},
               avg_duration: 200,
               p50_duration: 200,
               p90_duration: 280,
               p99_duration: 298
             }
    end

    test "returns zeroed analytics when no runs fall within the given period" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 0,
        duration: 100,
        ran_at: ~N[2024-04-10 10:00:00.000000],
        inserted_at: ~N[2024-04-30 10:00:00.000000]
      )

      # When
      got =
        Analytics.test_case_analytics_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-29 00:00:00Z],
          end_datetime: ~U[2024-05-01 00:00:00Z]
        )

      # Then - ingested inside the period, but it did not run inside it
      assert got == %{
               total_count: 0,
               failed_count: 0,
               flaky_count: 0,
               outcome_counts: %{successful: 0, failed: 0, flaky: 0, quarantined: 0, skipped: 0},
               avg_duration: 0,
               p50_duration: 0,
               p90_duration: 0,
               p99_duration: 0
             }
    end

    test "reports a median a single stalled run cannot move" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for duration <- [100, 100, 100, 100, 100, 100, 100, 100, 100, 100_000] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: 0,
          duration: duration
        )
      end

      # When
      got = Analytics.test_case_analytics_by_id(project.id, test_case_id)

      # Then - the same distribution the Test Cases listing guards against
      assert got.total_count == 10
      assert got.avg_duration == 10_090
      assert got.p50_duration == 100
      assert got.p99_duration > got.p50_duration
    end
  end

  describe "test_case_duration_series_by_id/3" do
    test "buckets the duration of a single test case by day" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for {ran_at, duration} <- [
            {~N[2024-04-28 09:00:00.000000], 100},
            {~N[2024-04-28 11:00:00.000000], 300},
            {~N[2024-04-30 09:00:00.000000], 1000}
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          duration: duration,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      # When
      got =
        Analytics.test_case_duration_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.values == [200, nil, 1000]
    end

    test "leaves a bucket without runs empty rather than reading it as instant" do
      # Given - a test case that ran on one day of the window only
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        duration: 500,
        ran_at: ~N[2024-04-29 09:00:00.000000],
        inserted_at: ~N[2024-04-29 09:00:00.000000]
      )

      # When
      got =
        Analytics.test_case_duration_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then - a day the test case did not run says nothing, it does not say 0 ms
      assert got.values == [nil, 500, nil]
      assert got.p50_values == [nil, 500, nil]
      assert got.p90_values == [nil, 500, nil]
      assert got.p99_values == [nil, 500, nil]
    end

    test "separates the percentiles from the average within a bucket" do
      # Given - one stalled run among nine quick ones on the same day
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for duration <- [100, 100, 100, 100, 100, 100, 100, 100, 100, 100_000] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          duration: duration,
          ran_at: ~N[2024-04-29 09:00:00.000000],
          inserted_at: ~N[2024-04-29 09:00:00.000000]
        )
      end

      # When
      got =
        Analytics.test_case_duration_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then - the average carries the outlier the median does not
      assert got.values == [nil, 10_090, nil]
      assert got.p50_values == [nil, 100, nil]
      assert Enum.at(got.p99_values, 1) > Enum.at(got.p50_values, 1)
    end

    test "counts only the runs of the given test case in the given project" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      ran_at = ~N[2024-04-29 09:00:00.000000]

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        duration: 100,
        ran_at: ran_at,
        inserted_at: ran_at
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: UUIDv7.generate(),
        duration: 9000,
        ran_at: ran_at,
        inserted_at: ran_at
      )

      RunsFixtures.test_case_run_fixture(
        project_id: other_project.id,
        test_case_id: test_case_id,
        duration: 9000,
        ran_at: ran_at,
        inserted_at: ran_at
      )

      # When
      got =
        Analytics.test_case_duration_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.values == [nil, 100, nil]
    end

    test "buckets by hour over a period of a day or less" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for {ran_at, duration} <- [
            {~N[2024-04-29 09:30:00.000000], 100},
            {~N[2024-04-29 11:30:00.000000], 900}
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          duration: duration,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      # When
      got =
        Analytics.test_case_duration_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-29 09:00:00Z],
          end_datetime: ~U[2024-04-29 11:59:59Z]
        )

      # Then
      assert got.dates == [
               ~U[2024-04-29 09:00:00Z],
               ~U[2024-04-29 10:00:00Z],
               ~U[2024-04-29 11:00:00Z]
             ]

      assert got.values == [100, nil, 900]
    end

    test "buckets by month over a period longer than two months" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for {ran_at, duration} <- [
            {~N[2024-03-15 09:00:00.000000], 100},
            {~N[2024-05-15 09:00:00.000000], 900}
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          duration: duration,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      # When
      got =
        Analytics.test_case_duration_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-03-01 00:00:00Z],
          end_datetime: ~U[2024-05-31 23:59:59Z]
        )

      # Then
      assert got.dates == [~D[2024-03-01], ~D[2024-04-01], ~D[2024-05-01]]
      assert got.values == [100, nil, 900]
    end

    test "excludes runs outside the period" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for {ran_at, duration} <- [
            {~N[2024-04-27 09:00:00.000000], 9000},
            {~N[2024-04-29 09:00:00.000000], 100}
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          duration: duration,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      # When
      got =
        Analytics.test_case_duration_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.values == [nil, 100, nil]
    end

    test "agrees with the summary widgets over a single bucket" do
      # Given - the widgets and the series read the same runs, so they cannot disagree
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for duration <- [100, 200, 300, 4000] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          duration: duration,
          ran_at: ~N[2024-04-29 09:00:00.000000],
          inserted_at: ~N[2024-04-29 09:00:00.000000]
        )
      end

      opts = [start_datetime: ~U[2024-04-29 00:00:00Z], end_datetime: ~U[2024-04-29 23:59:59Z]]

      # When
      series = Analytics.test_case_duration_series_by_id(project.id, test_case_id, opts)
      summary = Analytics.test_case_analytics_by_id(project.id, test_case_id, opts)

      # Then - every run sits in one bucket, so that bucket is the whole window
      assert Enum.reject(series.values, &is_nil/1) == [summary.avg_duration]
      assert Enum.reject(series.p50_values, &is_nil/1) == [summary.p50_duration]
      assert Enum.reject(series.p90_values, &is_nil/1) == [summary.p90_duration]
      assert Enum.reject(series.p99_values, &is_nil/1) == [summary.p99_duration]
    end
  end

  describe "test_case_run_series_by_id/3" do
    test "counts runs, failures and flakiness per bucket" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for {ran_at, status, is_flaky} <- [
            {~N[2024-04-28 09:00:00.000000], 0, false},
            {~N[2024-04-28 10:00:00.000000], 1, false},
            {~N[2024-04-28 11:00:00.000000], 0, true},
            {~N[2024-04-28 12:00:00.000000], 0, true},
            {~N[2024-04-30 09:00:00.000000], 1, false}
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: status,
          is_flaky: is_flaky,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      # When
      got =
        Analytics.test_case_run_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.run_counts == [4, 0, 1]
      assert got.failed_counts == [1, 0, 1]
      assert got.flakiness_rates == [50.0, nil, 0.0]
    end

    test "splits each bucket into segments that add up to its run count" do
      # Given - one run of every kind on one day
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      ran_at = ~N[2024-04-29 09:00:00.000000]

      for {status, is_flaky, is_quarantined} <- [
            {0, false, false},
            {1, false, false},
            {2, false, false},
            {0, true, false},
            {0, false, true}
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: status,
          is_flaky: is_flaky,
          is_quarantined: is_quarantined,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      # When
      got =
        Analytics.test_case_run_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.run_counts == [0, 5, 0]
      assert got.successful_counts == [0, 1, 0]
      assert got.failed_counts == [0, 1, 0]
      assert got.skipped_counts == [0, 1, 0]
      assert got.flaky_counts == [0, 1, 0]
      assert got.quarantined_counts == [0, 1, 0]
    end

    test "counts a run once, under the most specific segment it belongs to" do
      # Given - a run can be quarantined and flaky and failed at the same time,
      # and a stacked bar that counted it three times would overstate the day
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      ran_at = ~N[2024-04-29 09:00:00.000000]

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 1,
        is_flaky: true,
        is_quarantined: true,
        ran_at: ran_at,
        inserted_at: ran_at
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 1,
        is_flaky: true,
        ran_at: ran_at,
        inserted_at: ran_at
      )

      # When
      got =
        Analytics.test_case_run_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then - quarantined outranks flaky, which outranks the run's own status
      assert got.quarantined_counts == [0, 1, 0]
      assert got.flaky_counts == [0, 1, 0]
      assert got.failed_counts == [0, 0, 0]

      segments =
        Enum.zip([
          got.successful_counts,
          got.failed_counts,
          got.skipped_counts,
          got.flaky_counts,
          got.quarantined_counts
        ])

      assert Enum.map(segments, fn segment -> segment |> Tuple.to_list() |> Enum.sum() end) ==
               got.run_counts
    end

    test "leaves the flakiness rate of a bucket without runs empty" do
      # Given - a rate needs runs to be a rate, and 0% would claim the test never flaked
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        ran_at: ~N[2024-04-29 09:00:00.000000],
        inserted_at: ~N[2024-04-29 09:00:00.000000]
      )

      # When
      got =
        Analytics.test_case_run_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then - a count of zero runs is a fact, a rate over zero runs is not
      assert got.run_counts == [0, 1, 0]
      assert got.flakiness_rates == [nil, 0.0, nil]
    end

    test "counts only the runs of the given test case in the given project" do
      # Given
      project = ProjectsFixtures.project_fixture()
      other_project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      ran_at = ~N[2024-04-29 09:00:00.000000]

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        ran_at: ran_at,
        inserted_at: ran_at
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: UUIDv7.generate(),
        ran_at: ran_at,
        inserted_at: ran_at
      )

      RunsFixtures.test_case_run_fixture(
        project_id: other_project.id,
        test_case_id: test_case_id,
        ran_at: ran_at,
        inserted_at: ran_at
      )

      # When
      got =
        Analytics.test_case_run_series_by_id(project.id, test_case_id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.run_counts == [0, 1, 0]
    end

    test "agrees with the summary widgets over the window" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for {ran_at, status} <- [
            {~N[2024-04-28 09:00:00.000000], 0},
            {~N[2024-04-29 09:00:00.000000], 1},
            {~N[2024-04-30 09:00:00.000000], 0}
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: status,
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      opts = [start_datetime: ~U[2024-04-28 00:00:00Z], end_datetime: ~U[2024-04-30 23:59:59Z]]

      # When
      series = Analytics.test_case_run_series_by_id(project.id, test_case_id, opts)
      summary = Analytics.test_case_analytics_by_id(project.id, test_case_id, opts)

      # Then
      assert Enum.sum(series.run_counts) == summary.total_count
      assert Enum.sum(series.failed_counts) == summary.failed_count
    end
  end

  describe "test_case_reliability_series_by_id/4" do
    test "reports the success rate of each bucket on the default branch" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      for {ran_at, status} <- [
            {~N[2024-04-28 09:00:00.000000], 0},
            {~N[2024-04-28 10:00:00.000000], 1},
            {~N[2024-04-30 09:00:00.000000], 0}
          ] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: status,
          git_branch: "main",
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      # When
      got =
        Analytics.test_case_reliability_series_by_id(project.id, test_case_id, "main",
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.dates == [~D[2024-04-28], ~D[2024-04-29], ~D[2024-04-30]]
      assert got.values == [50.0, nil, 100.0]
    end

    test "ignores branches other than the default one when it has runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      ran_at = ~N[2024-04-29 09:00:00.000000]

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 0,
        git_branch: "main",
        ran_at: ran_at,
        inserted_at: ran_at
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        status: 1,
        git_branch: "feature",
        ran_at: ran_at,
        inserted_at: ran_at
      )

      # When
      got =
        Analytics.test_case_reliability_series_by_id(project.id, test_case_id, "main",
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then - the failing feature-branch run is out of scope, as it is for the widget
      assert got.values == [nil, 100.0, nil]
    end

    test "falls back to every branch when the default branch has no runs in the window" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()
      ran_at = ~N[2024-04-29 09:00:00.000000]

      for status <- [0, 1] do
        RunsFixtures.test_case_run_fixture(
          project_id: project.id,
          test_case_id: test_case_id,
          status: status,
          git_branch: "feature",
          ran_at: ran_at,
          inserted_at: ran_at
        )
      end

      opts = [start_datetime: ~U[2024-04-28 00:00:00Z], end_datetime: ~U[2024-04-30 23:59:59Z]]

      # When
      got = Analytics.test_case_reliability_series_by_id(project.id, test_case_id, "main", opts)

      # Then - the same fallback the widget makes, so the chart plots the number it shows
      assert got.values == [nil, 50.0, nil]
      assert Analytics.test_case_reliability_by_id(project.id, test_case_id, "main", opts) == 50.0
    end

    test "reports no reliability at all when the window holds no runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      # When
      got =
        Analytics.test_case_reliability_series_by_id(project.id, test_case_id, "main",
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.values == [nil, nil, nil]
    end
  end

  describe "test_duration_metric_by_count/3" do
    test "returns average duration for last N tests" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create tests with different durations (newest first)
      for {duration, i} <- [{3000, 1}, {2000, 2}, {1000, 3}] do
        {:ok, _} =
          RunsFixtures.test_fixture(
            project_id: project.id,
            duration: duration,
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -i * 60, :second)
          )
      end

      # When - get average of all 3 tests
      result = Analytics.test_duration_metric_by_count(project.id, :average, limit: 3)

      # Then
      assert result == 2000.0
    end

    test "returns p50 duration for last N tests" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create 5 tests with durations
      for {duration, i} <- [{5000, 1}, {4000, 2}, {3000, 3}, {2000, 4}, {1000, 5}] do
        {:ok, _} =
          RunsFixtures.test_fixture(
            project_id: project.id,
            duration: duration,
            ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -i * 60, :second)
          )
      end

      # When - get p50 of all 5 tests
      result = Analytics.test_duration_metric_by_count(project.id, :p50, limit: 5)

      # Then - p50 of sorted [1000, 2000, 3000, 4000, 5000] is 3000
      assert result == 3000
    end

    test "returns nil when no tests exist" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      result = Analytics.test_duration_metric_by_count(project.id, :average, limit: 5)

      # Then
      assert result == nil
    end
  end

  describe "get_test_case_flakiness_rate/1" do
    test "returns flakiness rate as percentage when there are flaky runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id)
      inserted_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_naive()

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: true,
        inserted_at: inserted_at
      )

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: false,
        inserted_at: inserted_at
      )

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: false,
        inserted_at: inserted_at
      )

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: true,
        inserted_at: inserted_at
      )

      # When
      got = Analytics.get_test_case_flakiness_rate(test_case)

      # Then - 2 flaky runs out of 4 total = 50%
      assert got == 50.0
    end

    test "returns 0.0 when there are no flaky runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id)
      inserted_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_naive()

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: false,
        inserted_at: inserted_at
      )

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: false,
        inserted_at: inserted_at
      )

      # When
      got = Analytics.get_test_case_flakiness_rate(test_case)

      # Then
      assert got == 0.0
    end

    test "returns 0.0 when there are no runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id)

      # When
      got = Analytics.get_test_case_flakiness_rate(test_case)

      # Then
      assert got == 0.0
    end

    test "only counts runs from the last 30 days" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id)

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: true,
        ran_at: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_naive()
      )

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: true,
        ran_at: DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.to_naive()
      )

      # When
      got = Analytics.get_test_case_flakiness_rate(test_case)

      # Then - Only 1 flaky run in the last 30 days out of 1 total = 100%
      assert got == 100.0
    end

    test "counts a run that executed inside the period but was ingested after it" do
      # Given - xcresult processing is asynchronous, so a run can land in
      # ClickHouse well after the window it belongs to.
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id)

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: true,
        ran_at: ~N[2024-04-30 10:00:00.000000],
        inserted_at: ~N[2024-05-20 10:00:00.000000]
      )

      # When
      got =
        Analytics.get_test_case_flakiness_rate(test_case,
          start_datetime: ~U[2024-04-29 00:00:00Z],
          end_datetime: ~U[2024-05-01 00:00:00Z]
        )

      # Then
      assert got == 100.0
    end

    test "only counts runs within the given period" do
      # Given
      project = ProjectsFixtures.project_fixture()
      test_case = RunsFixtures.test_case_fixture(project_id: project.id)

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: true,
        ran_at: ~N[2024-04-30 10:00:00.000000],
        inserted_at: ~N[2024-05-20 10:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: false,
        ran_at: ~N[2024-04-30 10:01:00.000000],
        inserted_at: ~N[2024-05-20 10:01:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: true,
        ran_at: ~N[2024-04-10 10:00:00.000000],
        inserted_at: ~N[2024-04-30 10:00:00.000000]
      )

      # When
      got =
        Analytics.get_test_case_flakiness_rate(test_case,
          start_datetime: ~U[2024-04-29 00:00:00Z],
          end_datetime: ~U[2024-05-01 00:00:00Z]
        )

      # Then - 1 flaky run out of the 2 that fall inside the period
      assert got == 50.0
    end
  end

  describe "test_run_duration_scatter_data/2" do
    test "returns individual test run data points grouped by scheme by default" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      {:ok, test_run_1} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          scheme: "AppScheme",
          duration: 1500,
          status: "success",
          is_ci: true,
          ran_at: ~N[2024-04-30 08:00:00.000000]
        )

      {:ok, test_run_2} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          scheme: "TestScheme",
          duration: 3000,
          status: "failure",
          is_ci: false,
          ran_at: ~N[2024-04-30 09:00:00.000000]
        )

      RunsFixtures.optimize_test_runs()

      # When
      got =
        Analytics.test_run_duration_scatter_data(
          project.id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.truncated == false
      assert got.oldest_entry == nil
      assert length(got.series) == 2

      app_series = Enum.find(got.series, &(&1.name == "AppScheme"))
      test_series = Enum.find(got.series, &(&1.name == "TestScheme"))

      assert app_series
      assert test_series

      [app_point] = app_series.data
      assert [_ts, 1500] = app_point.value
      assert app_point.id == test_run_1.id

      assert app_point.meta.scheme == "AppScheme"
      assert app_point.meta.status == "success"
      assert app_point.meta.is_ci == true

      [test_point] = test_series.data
      assert [_ts, 3000] = test_point.value
      assert test_point.id == test_run_2.id

      assert test_point.meta.scheme == "TestScheme"
      assert test_point.meta.status == "failure"
      assert test_point.meta.is_ci == false
    end

    test "respects group_by: :environment option" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      {:ok, _ci_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          scheme: "AppScheme",
          duration: 1000,
          status: "success",
          is_ci: true,
          ran_at: ~N[2024-04-30 08:00:00.000000]
        )

      {:ok, _local_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          scheme: "AppScheme",
          duration: 2000,
          status: "success",
          is_ci: false,
          ran_at: ~N[2024-04-30 09:00:00.000000]
        )

      RunsFixtures.optimize_test_runs()

      # When
      got =
        Analytics.test_run_duration_scatter_data(
          project.id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z],
          group_by: :environment
        )

      # Then
      assert length(got.series) == 2

      ci_series = Enum.find(got.series, &(&1.name == true))
      local_series = Enum.find(got.series, &(&1.name == false))

      assert ci_series
      assert local_series
      assert length(ci_series.data) == 1
      assert length(local_series.data) == 1
    end

    test "returns empty series when no test runs exist" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:20:30Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        Analytics.test_run_duration_scatter_data(
          project.id,
          start_datetime: ~U[2024-04-28 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.series == []
      assert got.truncated == false
      assert got.oldest_entry == nil
    end
  end

  describe "quarantined_tests_analytics/2" do
    test "returns empty analytics when no quarantine events exist" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.count == 0
      assert got.muted_count == 0
      assert got.skipped_count == 0
      assert got.trend == 0.0
      assert got.muted_trend == 0.0
      assert got.skipped_trend == 0.0
      assert Enum.all?(got.values, &(&1 == 0))
      assert Enum.all?(got.muted_values, &(&1 == 0))
      assert Enum.all?(got.skipped_values, &(&1 == 0))
    end

    test "counts muted test correctly" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [TuistTestSupport.Utilities.insertable_attrs(test_case)])

      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-15 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.muted_count == 1
      assert got.skipped_count == 0

      # Find index for April 15 (dates are Date structs)
      april_15_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-15]))

      if april_15_index do
        values_after = Enum.drop(got.muted_values, april_15_index)
        assert Enum.all?(values_after, &(&1 == 1))
      end

      assert Enum.all?(got.skipped_values, &(&1 == 0))
    end

    test "unmuting a test decreases muted count by exactly one" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: false,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [TuistTestSupport.Utilities.insertable_attrs(test_case)])

      # Mute on April 10
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # Unmute on April 20
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "unmuted",
        inserted_at: ~N[2024-04-20 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.muted_count == 0
      assert got.skipped_count == 0

      # Find indices for April 10 and April 20 (dates are Date structs)
      april_10_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-10]))
      april_20_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-20]))

      assert april_10_index != nil, "April 10 should be in dates"
      assert april_20_index != nil, "April 20 should be in dates"

      # Before April 10: should be 0
      values_before_10 = Enum.take(got.muted_values, april_10_index)
      assert Enum.all?(values_before_10, &(&1 == 0)), "Values before mute should be 0"

      # Between April 10 and April 19: should be 1
      values_between = Enum.slice(got.muted_values, april_10_index..(april_20_index - 1))

      assert Enum.all?(values_between, &(&1 == 1)),
             "Values between mute and unmute should be 1, got: #{inspect(values_between)}"

      # April 20 onwards: should be 0
      values_after_20 = Enum.drop(got.muted_values, april_20_index)

      assert Enum.all?(values_after_20, &(&1 == 0)),
             "Values after unmute should be 0, got: #{inspect(values_after_20)}"
    end

    test "multiple mute/unmute cycles are tracked correctly" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [TuistTestSupport.Utilities.insertable_attrs(test_case)])

      # First mute on April 5
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-05 12:00:00.000000]
      )

      # First unmute on April 10
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "unmuted",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # Second mute on April 20
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-20 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.muted_count == 1
      assert got.skipped_count == 0

      april_05_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-05]))
      april_10_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-10]))
      april_20_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-20]))

      assert april_05_index
      assert april_10_index
      assert april_20_index

      # Before April 5: should be 0
      values_before_5 = Enum.take(got.muted_values, april_05_index)
      assert Enum.all?(values_before_5, &(&1 == 0))

      # April 5 to April 9: should be 1
      values_5_to_10 = Enum.slice(got.muted_values, april_05_index..(april_10_index - 1))
      assert Enum.all?(values_5_to_10, &(&1 == 1))

      # April 10 to April 19: should be 0
      values_10_to_20 = Enum.slice(got.muted_values, april_10_index..(april_20_index - 1))
      assert Enum.all?(values_10_to_20, &(&1 == 0))

      # April 20 onwards: should be 1
      values_after_20 = Enum.drop(got.muted_values, april_20_index)
      assert Enum.all?(values_after_20, &(&1 == 1))
    end

    test "initial count includes events before the period" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: true,
          inserted_at: ~N[2024-03-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [TuistTestSupport.Utilities.insertable_attrs(test_case)])

      # Mute BEFORE the period (March 15)
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "muted",
        inserted_at: ~N[2024-03-15 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then - all muted values should be 1 since test was muted before period started
      assert got.muted_count == 1
      assert got.skipped_count == 0
      # Previous count (March 31) = 1, current = 1, so trend stays flat
      assert got.trend == 0.0
      assert got.muted_trend == 0.0
      assert Enum.all?(got.muted_values, &(&1 == 1))
      assert Enum.all?(got.skipped_values, &(&1 == 0))
    end

    test "trend reflects change between period start and end" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case_1 =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "muted_before_period",
          is_quarantined: true,
          inserted_at: ~N[2024-03-01 00:00:00.000000]
        )

      test_case_2 =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "muted_during_period",
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      test_case_3 =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "skipped_during_period",
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [
        TuistTestSupport.Utilities.insertable_attrs(test_case_1),
        TuistTestSupport.Utilities.insertable_attrs(test_case_2),
        TuistTestSupport.Utilities.insertable_attrs(test_case_3)
      ])

      # test 1 muted before the period (March 15)
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_1.id,
        event_type: "muted",
        inserted_at: ~N[2024-03-15 12:00:00.000000]
      )

      # test 2 muted during the period (April 10)
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_2.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # test 3 skipped during the period (April 15) — no skipped tests at start
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_3.id,
        event_type: "skipped",
        inserted_at: ~N[2024-04-15 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      # previous (March 31): muted=1, skipped=0, total=1
      # current: muted=2, skipped=1, total=3
      assert got.muted_count == 2
      assert got.skipped_count == 1
      assert got.count == 3
      # muted: 2/1 - 1 = 100%
      assert got.muted_trend == 100.0
      # skipped: previous=0 short-circuits to 0
      assert got.skipped_trend == 0.0
      # combined: 3/1 - 1 = 200%
      assert got.trend == 200.0
    end

    test "multiple test cases are counted independently" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case_1 =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "test1",
          is_quarantined: false,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      test_case_2 =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "test2",
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [
        TuistTestSupport.Utilities.insertable_attrs(test_case_1),
        TuistTestSupport.Utilities.insertable_attrs(test_case_2)
      ])

      # Mute test 1 on April 10
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_1.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # Mute test 2 on April 15
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_2.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-15 12:00:00.000000]
      )

      # Unmute test 1 on April 20
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_1.id,
        event_type: "unmuted",
        inserted_at: ~N[2024-04-20 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then - test_case_2 is muted at the end
      assert got.muted_count == 1
      assert got.skipped_count == 0

      april_10_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-10]))
      april_15_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-15]))
      april_20_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-20]))

      assert april_10_index
      assert april_15_index
      assert april_20_index

      # Before April 10: should be 0
      values_before_10 = Enum.take(got.muted_values, april_10_index)
      assert Enum.all?(values_before_10, &(&1 == 0))

      # April 10 to April 14: should be 1 (only test 1)
      values_10_to_15 = Enum.slice(got.muted_values, april_10_index..(april_15_index - 1))
      assert Enum.all?(values_10_to_15, &(&1 == 1))

      # April 15 to April 19: should be 2 (both tests)
      values_15_to_20 = Enum.slice(got.muted_values, april_15_index..(april_20_index - 1))
      assert Enum.all?(values_15_to_20, &(&1 == 2))

      # April 20 onwards: should be 1 (only test 2)
      values_after_20 = Enum.drop(got.muted_values, april_20_index)
      assert Enum.all?(values_after_20, &(&1 == 1))
    end

    test "chart values are not inflated by duplicate mute events" do
      # Simulates pre-fix behavior: ingestion silently resets is_quarantined
      # without creating "unmuted" events, then auto-quarantine creates
      # another "muted" event. This should NOT inflate the chart count.
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [TuistTestSupport.Utilities.insertable_attrs(test_case)])

      # First mute event
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-05 12:00:00.000000]
      )

      # Duplicate mute events (no matching unmute events)
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-15 12:00:00.000000]
      )

      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      assert got.muted_count == 1
      assert Enum.max(got.muted_values) <= 1
      assert got.skipped_count == 0
    end

    test "counts skipped tests separately from muted tests" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case_1 =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "test_muted",
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      test_case_2 =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          name: "test_skipped",
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [
        TuistTestSupport.Utilities.insertable_attrs(test_case_1),
        TuistTestSupport.Utilities.insertable_attrs(test_case_2)
      ])

      # Mute test 1 on April 10
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_1.id,
        event_type: "muted",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # Skip test 2 on April 15
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_2.id,
        event_type: "skipped",
        inserted_at: ~N[2024-04-15 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.muted_count == 1
      assert got.skipped_count == 1
      assert got.count == 2

      april_10_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-10]))
      april_15_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-15]))

      assert april_10_index
      assert april_15_index

      # Before April 10: both should be 0
      assert Enum.all?(Enum.take(got.muted_values, april_10_index), &(&1 == 0))
      assert Enum.all?(Enum.take(got.skipped_values, april_10_index), &(&1 == 0))
      assert Enum.all?(Enum.take(got.values, april_10_index), &(&1 == 0))

      # April 10 to April 14: muted=1, skipped=0, total=1
      muted_10_to_15 = Enum.slice(got.muted_values, april_10_index..(april_15_index - 1))
      skipped_10_to_15 = Enum.slice(got.skipped_values, april_10_index..(april_15_index - 1))
      total_10_to_15 = Enum.slice(got.values, april_10_index..(april_15_index - 1))
      assert Enum.all?(muted_10_to_15, &(&1 == 1))
      assert Enum.all?(skipped_10_to_15, &(&1 == 0))
      assert Enum.all?(total_10_to_15, &(&1 == 1))

      # April 15 onwards: muted=1, skipped=1, total=2
      muted_after_15 = Enum.drop(got.muted_values, april_15_index)
      skipped_after_15 = Enum.drop(got.skipped_values, april_15_index)
      total_after_15 = Enum.drop(got.values, april_15_index)
      assert Enum.all?(muted_after_15, &(&1 == 1))
      assert Enum.all?(skipped_after_15, &(&1 == 1))
      assert Enum.all?(total_after_15, &(&1 == 2))
    end

    test "unskipping a test decreases skipped count" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [TuistTestSupport.Utilities.insertable_attrs(test_case)])

      # Skip on April 10
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "skipped",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # Unskip on April 20
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "unskipped",
        inserted_at: ~N[2024-04-20 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.muted_count == 0
      assert got.skipped_count == 0

      april_10_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-10]))
      april_20_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-20]))

      # Between April 10 and April 19: skipped should be 1
      skipped_between = Enum.slice(got.skipped_values, april_10_index..(april_20_index - 1))
      assert Enum.all?(skipped_between, &(&1 == 1))

      # After April 20: skipped should be 0
      skipped_after = Enum.drop(got.skipped_values, april_20_index)
      assert Enum.all?(skipped_after, &(&1 == 0))

      # Muted should always be 0
      assert Enum.all?(got.muted_values, &(&1 == 0))
    end
  end

  describe "flaky_test_case_runs_analytics/2" do
    test "returns zero when no flaky test case runs exist" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        Analytics.flaky_test_case_runs_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.count == 0
      assert Enum.all?(got.values, &(&1 == 0))
    end

    test "counts every flaky test case execution in the period and ignores non-flaky runs" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()
      test_case_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        is_flaky: true,
        ran_at: ~N[2024-04-10 09:00:00.000000],
        inserted_at: ~N[2024-04-10 09:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        is_flaky: true,
        ran_at: ~N[2024-04-15 09:00:00.000000],
        inserted_at: ~N[2024-04-15 09:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: test_case_id,
        is_flaky: false,
        ran_at: ~N[2024-04-15 10:00:00.000000],
        inserted_at: ~N[2024-04-15 10:00:00.000000]
      )

      RunsFixtures.optimize_test_case_runs()

      # When
      got =
        Analytics.flaky_test_case_runs_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.count == 2
    end

    test "excludes runs outside the date range" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        is_flaky: true,
        ran_at: ~N[2024-03-15 09:00:00.000000],
        inserted_at: ~N[2024-03-15 09:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        is_flaky: true,
        ran_at: ~N[2024-04-15 09:00:00.000000],
        inserted_at: ~N[2024-04-15 09:00:00.000000]
      )

      RunsFixtures.optimize_test_case_runs()

      # When
      got =
        Analytics.flaky_test_case_runs_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.count == 1
    end

    test "honors the is_ci filter" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        is_flaky: true,
        is_ci: true,
        ran_at: ~N[2024-04-10 09:00:00.000000],
        inserted_at: ~N[2024-04-10 09:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        is_flaky: true,
        is_ci: false,
        ran_at: ~N[2024-04-15 09:00:00.000000],
        inserted_at: ~N[2024-04-15 09:00:00.000000]
      )

      RunsFixtures.optimize_test_case_runs()

      base_opts = [start_datetime: ~U[2024-04-01 00:00:00Z], end_datetime: ~U[2024-04-30 23:59:59Z]]

      # When
      any_env = Analytics.flaky_test_case_runs_analytics(project.id, base_opts)
      ci_only = Analytics.flaky_test_case_runs_analytics(project.id, Keyword.put(base_opts, :is_ci, true))
      local_only = Analytics.flaky_test_case_runs_analytics(project.id, Keyword.put(base_opts, :is_ci, false))

      # Then
      assert any_env.count == 2
      assert ci_only.count == 1
      assert local_only.count == 1
    end

    test "computes trend by comparing the current period to the equivalent prior period" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      # One flaky run in the prior 30-day window
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        is_flaky: true,
        ran_at: ~N[2024-03-10 09:00:00.000000],
        inserted_at: ~N[2024-03-10 09:00:00.000000]
      )

      # Two flaky runs in the current 30-day window
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        is_flaky: true,
        ran_at: ~N[2024-04-05 09:00:00.000000],
        inserted_at: ~N[2024-04-05 09:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        is_flaky: true,
        ran_at: ~N[2024-04-20 09:00:00.000000],
        inserted_at: ~N[2024-04-20 09:00:00.000000]
      )

      RunsFixtures.optimize_test_case_runs()

      # When
      got =
        Analytics.flaky_test_case_runs_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.count == 2
      assert got.trend == 100.0
    end
  end

  describe "flaky_tests_analytics/2" do
    test "returns zero when no test cases are flagged as flaky" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        Analytics.flaky_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.count == 0
      assert Enum.all?(got.values, &(&1 == 0))
    end

    test "reflects marked_flaky / unmarked_flaky events across the period" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_flaky: false,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [TuistTestSupport.Utilities.insertable_attrs(test_case)])

      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "marked_flaky",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "unmarked_flaky",
        inserted_at: ~N[2024-04-20 12:00:00.000000]
      )

      # When
      got =
        Analytics.flaky_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      april_5_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-05]))
      april_15_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-15]))
      april_25_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-25]))

      assert Enum.at(got.values, april_5_index) == 0
      assert Enum.at(got.values, april_15_index) == 1
      assert Enum.at(got.values, april_25_index) == 0

      assert got.count == Enum.at(got.values, -1)
    end

    test "honors the is_ci filter by scoping to test cases with matching runs in the period" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      ci_tc =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_flaky: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      local_tc =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_flaky: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [
        TuistTestSupport.Utilities.insertable_attrs(ci_tc),
        TuistTestSupport.Utilities.insertable_attrs(local_tc)
      ])

      # Each one marked flaky mid-period
      RunsFixtures.test_case_event_fixture(
        test_case_id: ci_tc.id,
        event_type: "marked_flaky",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      RunsFixtures.test_case_event_fixture(
        test_case_id: local_tc.id,
        event_type: "marked_flaky",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # CI-only test case has a CI run within the period; local-only has a local run
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: ci_tc.id,
        is_ci: true,
        ran_at: ~N[2024-04-15 09:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: local_tc.id,
        is_ci: false,
        ran_at: ~N[2024-04-15 09:00:00.000000]
      )

      base_opts = [start_datetime: ~U[2024-04-01 00:00:00Z], end_datetime: ~U[2024-04-30 23:59:59Z]]

      any_env = Analytics.flaky_tests_analytics(project.id, base_opts)
      ci_only = Analytics.flaky_tests_analytics(project.id, Keyword.put(base_opts, :is_ci, true))
      local_only = Analytics.flaky_tests_analytics(project.id, Keyword.put(base_opts, :is_ci, false))

      # Then
      assert any_env.count == 2
      assert ci_only.count == 1
      assert local_only.count == 1
    end
  end

  describe "test_cases_count_analytics/2" do
    test "returns zero when no test cases have runs" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      # When
      got =
        Analytics.test_cases_count_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      assert got.count == 0
      assert Enum.all?(got.values, &(&1 == 0))
    end

    test "counts distinct test cases active within the 14-day window and drops when runs stop" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      tc_a_id = UUIDv7.generate()
      tc_b_id = UUIDv7.generate()

      # Test case A: runs April 5 only (so active April 5 → April 19, drops off April 20+)
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: tc_a_id,
        ran_at: ~N[2024-04-05 09:00:00.000000]
      )

      # Test case B: runs on April 20 (active April 20 → end)
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: tc_b_id,
        ran_at: ~N[2024-04-20 09:00:00.000000]
      )

      # When
      got =
        Analytics.test_cases_count_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then
      april_4_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-04]))
      april_10_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-10]))
      april_18_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-18]))
      april_20_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-20]))
      april_25_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-25]))

      # Before any run
      assert Enum.at(got.values, april_4_index) == 0
      # Only A within window
      assert Enum.at(got.values, april_10_index) == 1
      # A still within 14d of April 5
      assert Enum.at(got.values, april_18_index) == 1
      # B now active, A still within 14d (April 5 + 14 = April 19)
      assert Enum.at(got.values, april_20_index) == 1
      # A has dropped off (April 25 is >14d after April 5), B still active
      assert Enum.at(got.values, april_25_index) == 1

      # Current count reflects state at end_datetime
      assert got.count == Enum.at(got.values, -1)
    end

    test "honors the is_ci filter" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      ci_only_id = UUIDv7.generate()
      local_only_id = UUIDv7.generate()

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: ci_only_id,
        is_ci: true,
        ran_at: ~N[2024-04-20 09:00:00.000000]
      )

      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: local_only_id,
        is_ci: false,
        ran_at: ~N[2024-04-20 09:00:00.000000]
      )

      base_opts = [start_datetime: ~U[2024-04-01 00:00:00Z], end_datetime: ~U[2024-04-30 23:59:59Z]]

      any_env = Analytics.test_cases_count_analytics(project.id, base_opts)
      ci_only = Analytics.test_cases_count_analytics(project.id, Keyword.put(base_opts, :is_ci, true))
      local_only = Analytics.test_cases_count_analytics(project.id, Keyword.put(base_opts, :is_ci, false))

      # Then
      assert any_env.count == 2
      assert ci_only.count == 1
      assert local_only.count == 1
    end

    # The day-grain MV is too coarse for hourly buckets — a test case that
    # ran later in the day must not appear in earlier hourly buckets, and the
    # count must change hour-to-hour as the rolling window shifts. The
    # `:hour` branch falls back to the raw `test_case_runs` query.
    test "uses second-precise window for hourly buckets (last-24-hours preset)" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 12:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      tc_id = UUIDv7.generate()

      # Test case ran at 09:30 today — should be visible from the 10:00 bucket
      # onward, but not from the 09:00 bucket (which ends at 09:59:59 — the
      # run is at 09:30, so it would actually be in 09:00's bucket via the
      # raw query if endpoint is ≥ 09:30; we choose 08:00 to make the assert
      # unambiguous).
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_case_id: tc_id,
        ran_at: ~N[2024-04-30 09:30:00.000000]
      )

      # When — hourly chart spanning the past 24 hours
      got =
        Analytics.test_cases_count_analytics(
          project.id,
          start_datetime: ~U[2024-04-29 12:00:00Z],
          end_datetime: ~U[2024-04-30 12:00:00Z]
        )

      # Then — the bucket whose endpoint is before 09:30 must report 0; the
      # bucket whose endpoint is after must report 1. With the day-grain MV
      # both buckets would return the same value (counting the 09:30 run for
      # the entire day), which is what this test guards against.
      bucket_at = fn datetime ->
        idx = Enum.find_index(got.dates, &(DateTime.compare(&1, datetime) == :eq))
        Enum.at(got.values, idx)
      end

      assert bucket_at.(~U[2024-04-30 08:00:00Z]) == 0
      assert bucket_at.(~U[2024-04-30 10:00:00Z]) == 1
    end
  end
end
