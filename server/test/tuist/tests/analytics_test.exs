defmodule Tuist.Tests.AnalyticsTest do
  use TuistTestSupport.Cases.DataCase
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

      {:ok, test_run, _} =
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

      {:ok, test_run, _} =
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

      {:ok, test_run, _} =
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

  describe "test_runs_metrics/1" do
    test "returns metrics and command event data for test runs" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # Create test runs
      {:ok, test_run_one, _} =
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

      {:ok, test_run_two, _} =
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
      got = Analytics.test_runs_metrics([test_run_one, test_run_two])

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

      {:ok, test_run, _} =
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
      got = Analytics.test_runs_metrics([test_run])

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

      {:ok, test_run, _} =
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

      {:ok, ci_test_run, _} =
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

      {:ok, local_test_run, _} =
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

      {:ok, test_run, _} =
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

      {:ok, test_run, _} =
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

      {:ok, ci_test_run, _} =
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

      {:ok, local_test_run, _} =
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

      {:ok, _test_run_1, _} =
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

      {:ok, _test_run_2, _} =
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

      {:ok, _test_run_3, _} =
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

      {:ok, _ci_test_run, _} =
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

      {:ok, _local_test_run, _} =
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

  describe "test_case_reliability_by_id/2" do
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
      got = Analytics.test_case_reliability_by_id(test_case_id, "main")

      # Then - 2 successes out of 3 runs = 66.7%
      assert got == 66.7
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
      got = Analytics.test_case_reliability_by_id(test_case_id, "main")

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
      got = Analytics.test_case_reliability_by_id(test_case_id, "main")

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
      got = Analytics.test_case_reliability_by_id(test_case_id, "main")

      # Then - 1 success out of 2 runs = 50%
      assert got == 50.0
    end

    test "returns nil when no runs exist at all" do
      # Given
      test_case_id = UUIDv7.generate()

      # When
      got = Analytics.test_case_reliability_by_id(test_case_id, "main")

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
      got = Analytics.test_case_reliability_by_id(test_case_id, "main")

      # Then - 0 successes out of 1 run on main = 0%
      assert got == 0.0
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
        inserted_at: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_naive()
      )

      RunsFixtures.test_case_run_fixture(
        test_case_id: test_case.id,
        project_id: project.id,
        is_flaky: true,
        inserted_at: DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.to_naive()
      )

      # When
      got = Analytics.get_test_case_flakiness_rate(test_case)

      # Then - Only 1 flaky run in the last 30 days out of 1 total = 100%
      assert got == 100.0
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
      assert Enum.all?(got.values, &(&1 == 0))
    end

    test "counts quarantined test correctly" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "quarantined",
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
      assert got.count == 1

      # Find index for April 15 (dates are Date structs)
      april_15_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-15]))

      if april_15_index do
        values_after = Enum.drop(got.values, april_15_index)
        assert Enum.all?(values_after, &(&1 == 1))
      end
    end

    test "unquarantining a test decreases count by exactly one" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: false,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # Quarantine on April 10
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "quarantined",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # Unquarantine on April 20
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "unquarantined",
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
      assert got.count == 0

      # Find indices for April 10 and April 20 (dates are Date structs)
      april_10_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-10]))
      april_20_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-20]))

      assert april_10_index != nil, "April 10 should be in dates"
      assert april_20_index != nil, "April 20 should be in dates"

      # Before April 10: should be 0
      values_before_10 = Enum.take(got.values, april_10_index)
      assert Enum.all?(values_before_10, &(&1 == 0)), "Values before quarantine should be 0"

      # Between April 10 and April 19: should be 1
      values_between = Enum.slice(got.values, april_10_index..(april_20_index - 1))

      assert Enum.all?(values_between, &(&1 == 1)),
             "Values between quarantine and unquarantine should be 1, got: #{inspect(values_between)}"

      # April 20 onwards: should be 0
      values_after_20 = Enum.drop(got.values, april_20_index)

      assert Enum.all?(values_after_20, &(&1 == 0)),
             "Values after unquarantine should be 0, got: #{inspect(values_after_20)}"
    end

    test "multiple quarantine/unquarantine cycles are tracked correctly" do
      # Given
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # First quarantine on April 5
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "quarantined",
        inserted_at: ~N[2024-04-05 12:00:00.000000]
      )

      # First unquarantine on April 10
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "unquarantined",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # Second quarantine on April 20
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "quarantined",
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
      assert got.count == 1

      april_05_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-05]))
      april_10_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-10]))
      april_20_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-20]))

      assert april_05_index
      assert april_10_index
      assert april_20_index

      # Before April 5: should be 0
      values_before_5 = Enum.take(got.values, april_05_index)
      assert Enum.all?(values_before_5, &(&1 == 0))

      # April 5 to April 9: should be 1
      values_5_to_10 = Enum.slice(got.values, april_05_index..(april_10_index - 1))
      assert Enum.all?(values_5_to_10, &(&1 == 1))

      # April 10 to April 19: should be 0
      values_10_to_20 = Enum.slice(got.values, april_10_index..(april_20_index - 1))
      assert Enum.all?(values_10_to_20, &(&1 == 0))

      # April 20 onwards: should be 1
      values_after_20 = Enum.drop(got.values, april_20_index)
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

      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # Quarantine BEFORE the period (March 15)
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "quarantined",
        inserted_at: ~N[2024-03-15 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then - all values should be 1 since test was quarantined before period started
      assert got.count == 1
      assert Enum.all?(got.values, &(&1 == 1))
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
        test_case_1 |> Map.from_struct() |> Map.delete(:__meta__),
        test_case_2 |> Map.from_struct() |> Map.delete(:__meta__)
      ])

      # Quarantine test 1 on April 10
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_1.id,
        event_type: "quarantined",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      # Quarantine test 2 on April 15
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_2.id,
        event_type: "quarantined",
        inserted_at: ~N[2024-04-15 12:00:00.000000]
      )

      # Unquarantine test 1 on April 20
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case_1.id,
        event_type: "unquarantined",
        inserted_at: ~N[2024-04-20 12:00:00.000000]
      )

      # When
      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      # Then - test_case_2 is quarantined at the end
      assert got.count == 1

      april_10_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-10]))
      april_15_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-15]))
      april_20_index = Enum.find_index(got.dates, &(&1 == ~D[2024-04-20]))

      assert april_10_index
      assert april_15_index
      assert april_20_index

      # Before April 10: should be 0
      values_before_10 = Enum.take(got.values, april_10_index)
      assert Enum.all?(values_before_10, &(&1 == 0))

      # April 10 to April 14: should be 1 (only test 1)
      values_10_to_15 = Enum.slice(got.values, april_10_index..(april_15_index - 1))
      assert Enum.all?(values_10_to_15, &(&1 == 1))

      # April 15 to April 19: should be 2 (both tests)
      values_15_to_20 = Enum.slice(got.values, april_15_index..(april_20_index - 1))
      assert Enum.all?(values_15_to_20, &(&1 == 2))

      # April 20 onwards: should be 1 (only test 2)
      values_after_20 = Enum.drop(got.values, april_20_index)
      assert Enum.all?(values_after_20, &(&1 == 1))
    end

    test "chart values are not inflated by duplicate quarantine events" do
      # Simulates pre-fix behavior: ingestion silently resets is_quarantined
      # without creating "unquarantined" events, then auto-quarantine creates
      # another "quarantined" event. This should NOT inflate the chart count.
      stub(DateTime, :utc_now, fn -> ~U[2024-04-30 10:00:00Z] end)
      project = ProjectsFixtures.project_fixture()

      test_case =
        RunsFixtures.test_case_fixture(
          project_id: project.id,
          is_quarantined: true,
          inserted_at: ~N[2024-04-01 00:00:00.000000]
        )

      IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

      # First quarantine event
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "quarantined",
        inserted_at: ~N[2024-04-05 12:00:00.000000]
      )

      # Duplicate quarantine events (no matching unquarantine events)
      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "quarantined",
        inserted_at: ~N[2024-04-10 12:00:00.000000]
      )

      RunsFixtures.test_case_event_fixture(
        test_case_id: test_case.id,
        event_type: "quarantined",
        inserted_at: ~N[2024-04-15 12:00:00.000000]
      )

      got =
        Analytics.quarantined_tests_analytics(
          project.id,
          start_datetime: ~U[2024-04-01 00:00:00Z],
          end_datetime: ~U[2024-04-30 23:59:59Z]
        )

      assert got.count == 1
      assert Enum.max(got.values) <= 1
    end
  end
end
