defmodule Tuist.Metrics.TelemetryTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Metrics
  alias Tuist.Metrics.Aggregator
  alias Tuist.Metrics.Telemetry, as: MetricsTelemetry
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    MetricsTelemetry.attach()
    on_exit(&MetricsTelemetry.detach/0)

    case GenServer.whereis(Aggregator) do
      nil -> start_supervised!(Aggregator)
      _ -> Aggregator.reset()
    end

    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    %{account: user.account, project: project}
  end

  test "bridges CLI run command events into the CLI counter and histogram", %{
    account: account,
    project: project
  } do
    command_event = %{
      project_id: project.id,
      name: "generate",
      is_ci: false,
      status: :success
    }

    :telemetry.execute(
      [:tuist, :run, :command],
      %{duration: 400},
      %{command_event: command_event}
    )

    _ = :sys.get_state(Aggregator)

    snapshot = Metrics.snapshot(account.id)

    assert Enum.any?(
             snapshot,
             &(&1.metric == "tuist_cli_invocations_total" and &1.value == 1)
           )

    assert Enum.any?(snapshot, fn entry ->
             entry.metric == "tuist_cli_invocation_duration_seconds" and
               entry.type == :histogram and
               entry.count == 1
           end)
  end

  test "bridges Xcode build metrics with account + project labels", %{account: account, project: project} do
    :telemetry.execute(
      [:tuist, :metrics, :xcode, :build, :run],
      %{duration_seconds: 1.5},
      %{
        account_id: account.id,
        project: "#{account.name}/#{project.name}",
        scheme: "App",
        is_ci: true,
        status: "success",
        xcode_version: "15.0",
        macos_version: "14.0"
      }
    )

    _ = :sys.get_state(Aggregator)

    snapshot = Metrics.snapshot(account.id)

    counter = Enum.find(snapshot, &(&1.metric == "tuist_xcode_build_runs_total"))
    assert counter.value == 1

    histogram =
      Enum.find(snapshot, &(&1.metric == "tuist_xcode_build_run_duration_seconds"))

    assert histogram.count == 1
    assert_in_delta histogram.sum, 1.5, 1.0e-6
  end

  test "bridges cache events into the Xcode cache counter", %{account: account, project: project} do
    :telemetry.execute(
      [:tuist, :cache, :event],
      %{count: 4},
      %{event_type: :local_hit, project_id: project.id}
    )

    _ = :sys.get_state(Aggregator)

    snapshot = Metrics.snapshot(account.id)

    assert Enum.any?(snapshot, fn entry ->
             entry.metric == "tuist_xcode_cache_events_total" and entry.value == 4 and
               elem(entry.labels, 1) == "local_hit"
           end)
  end

  test "bridges Xcode test run metrics into the test-run counter and histogram", %{
    account: account,
    project: project
  } do
    :telemetry.execute(
      [:tuist, :metrics, :xcode, :test, :run],
      %{duration_seconds: 2.25},
      %{
        account_id: account.id,
        project: "#{account.name}/#{project.name}",
        scheme: "AppTests",
        is_ci: true,
        status: "success",
        xcode_version: "15.4",
        macos_version: "14.6"
      }
    )

    _ = :sys.get_state(Aggregator)

    snapshot = Metrics.snapshot(account.id)

    counter = Enum.find(snapshot, &(&1.metric == "tuist_xcode_test_runs_total"))
    assert counter.value == 1

    histogram = Enum.find(snapshot, &(&1.metric == "tuist_xcode_test_run_duration_seconds"))
    assert histogram.count == 1
    assert_in_delta histogram.sum, 2.25, 1.0e-6
  end

  test "bridges Xcode test case aggregate into the test-cases counter", %{
    account: account,
    project: project
  } do
    :telemetry.execute(
      [:tuist, :metrics, :xcode, :test, :case],
      %{count: 7},
      %{
        account_id: account.id,
        project: "#{account.name}/#{project.name}",
        scheme: "AppTests",
        is_ci: false,
        status: "failure"
      }
    )

    _ = :sys.get_state(Aggregator)

    snapshot = Metrics.snapshot(account.id)

    counter = Enum.find(snapshot, &(&1.metric == "tuist_xcode_test_cases_total"))
    assert counter.value == 7
    # Labels are {project, scheme, is_ci, status}, all strings.
    assert elem(counter.labels, 3) == "failure"
  end

  test "bridges Gradle build metrics into the build counter and histogram", %{
    account: account,
    project: project
  } do
    :telemetry.execute(
      [:tuist, :metrics, :gradle, :build, :run],
      %{duration_seconds: 45.0},
      %{
        account_id: account.id,
        project: "#{account.name}/#{project.name}",
        module: "app",
        is_ci: true,
        status: "success",
        gradle_version: "8.5",
        jvm_version: "17"
      }
    )

    _ = :sys.get_state(Aggregator)

    snapshot = Metrics.snapshot(account.id)

    counter = Enum.find(snapshot, &(&1.metric == "tuist_gradle_build_runs_total"))
    assert counter.value == 1
    # Labels are {project, module, is_ci, status, gradle_version, jvm_version}.
    assert elem(counter.labels, 1) == "app"
    assert elem(counter.labels, 4) == "8.5"

    histogram = Enum.find(snapshot, &(&1.metric == "tuist_gradle_build_run_duration_seconds"))
    assert histogram.count == 1
    assert_in_delta histogram.sum, 45.0, 1.0e-6
  end

  test "bridges Gradle test run metrics into the test counter and histogram", %{
    account: account,
    project: project
  } do
    :telemetry.execute(
      [:tuist, :metrics, :gradle, :test, :run],
      %{duration_seconds: 8.0},
      %{
        account_id: account.id,
        project: "#{account.name}/#{project.name}",
        module: "feature",
        is_ci: false,
        status: "failure",
        gradle_version: "8.5",
        jvm_version: "17"
      }
    )

    _ = :sys.get_state(Aggregator)

    snapshot = Metrics.snapshot(account.id)

    counter = Enum.find(snapshot, &(&1.metric == "tuist_gradle_test_runs_total"))
    assert counter.value == 1
    assert elem(counter.labels, 3) == "failure"

    histogram = Enum.find(snapshot, &(&1.metric == "tuist_gradle_test_run_duration_seconds"))
    assert histogram.count == 1
    assert_in_delta histogram.sum, 8.0, 1.0e-6
  end
end
