defmodule TuistTestSupport.Fixtures.AlertsFixtures do
  @moduledoc false

  alias Tuist.Alerts.Alert
  alias Tuist.Alerts.AlertRule
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
      previous_value: Keyword.get(opts, :previous_value, 1000.0)
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
      threshold_percentage: Keyword.get(opts, :threshold_percentage, 20.0),
      sample_size: Keyword.get(opts, :sample_size, 100),
      enabled: Keyword.get(opts, :enabled, true),
      slack_channel_id: Keyword.get(opts, :slack_channel_id, "C#{unique_id}"),
      slack_channel_name: Keyword.get(opts, :slack_channel_name, "test-channel-#{unique_id}")
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end
end
