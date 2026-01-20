defmodule TuistTestSupport.Fixtures.AlertsFixtures do
  @moduledoc false

  alias Tuist.Alerts.Alert
  alias Tuist.Alerts.AlertRule
  alias Tuist.Alerts.FlakyTestAlert
  alias Tuist.Alerts.FlakyTestAlertRule
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def alert_fixture(opts \\ []) do
    alert_rule =
      Keyword.get_lazy(opts, :alert_rule, fn ->
        alert_rule_fixture()
      end)

    %Alert{}
    |> Alert.changeset(%{
      alert_rule_id: Keyword.get(opts, :alert_rule_id, alert_rule.id),
      current_value: Keyword.get(opts, :current_value, 1200.0),
      previous_value: Keyword.get(opts, :previous_value, 1000.0),
      inserted_at: Keyword.get(opts, :inserted_at)
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end

  def alert_rule_fixture(opts \\ []) do
    project =
      Keyword.get_lazy(opts, :project, fn ->
        ProjectsFixtures.project_fixture()
      end)

    unique_id = TuistTestSupport.Utilities.unique_integer()

    %AlertRule{}
    |> AlertRule.changeset(%{
      project_id: Keyword.get(opts, :project_id, project.id),
      name: Keyword.get(opts, :name, "Test Alert #{unique_id}"),
      category: Keyword.get(opts, :category, :build_run_duration),
      metric: Keyword.get(opts, :metric, :p90),
      deviation_percentage: Keyword.get(opts, :deviation_percentage, 20.0),
      rolling_window_size: Keyword.get(opts, :rolling_window_size, 100),
      slack_channel_id: Keyword.get(opts, :slack_channel_id, "C#{unique_id}"),
      slack_channel_name: Keyword.get(opts, :slack_channel_name, "test-channel-#{unique_id}")
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end

  def flaky_test_alert_fixture(opts \\ []) do
    flaky_test_alert_rule =
      Keyword.get_lazy(opts, :flaky_test_alert_rule, fn ->
        flaky_test_alert_rule_fixture()
      end)

    unique_id = TuistTestSupport.Utilities.unique_integer()

    %FlakyTestAlert{}
    |> FlakyTestAlert.changeset(%{
      flaky_test_alert_rule_id: Keyword.get(opts, :flaky_test_alert_rule_id, flaky_test_alert_rule.id),
      flaky_runs_count: Keyword.get(opts, :flaky_runs_count, 5),
      test_case_id: Keyword.get(opts, :test_case_id, Ecto.UUID.generate()),
      test_case_name: Keyword.get(opts, :test_case_name, "testExample#{unique_id}"),
      test_case_module_name: Keyword.get(opts, :test_case_module_name, "MyTests#{unique_id}"),
      test_case_suite_name: Keyword.get(opts, :test_case_suite_name, "TestSuite#{unique_id}"),
      inserted_at: Keyword.get(opts, :inserted_at)
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end

  def flaky_test_alert_rule_fixture(opts \\ []) do
    project =
      Keyword.get_lazy(opts, :project, fn ->
        ProjectsFixtures.project_fixture()
      end)

    unique_id = TuistTestSupport.Utilities.unique_integer()

    %FlakyTestAlertRule{}
    |> FlakyTestAlertRule.changeset(%{
      project_id: Keyword.get(opts, :project_id, project.id),
      name: Keyword.get(opts, :name, "Flaky Test Alert #{unique_id}"),
      trigger_threshold: Keyword.get(opts, :trigger_threshold, 5),
      slack_channel_id: Keyword.get(opts, :slack_channel_id, "C#{unique_id}"),
      slack_channel_name: Keyword.get(opts, :slack_channel_name, "flaky-alerts-#{unique_id}")
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end
end
