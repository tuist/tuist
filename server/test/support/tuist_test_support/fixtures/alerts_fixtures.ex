defmodule TuistTestSupport.Fixtures.AlertsFixtures do
  @moduledoc false

  alias Tuist.Alerts.AlertRule
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def alert_rule_fixture(opts \\ []) do
    project =
      Keyword.get_lazy(opts, :project, fn ->
        ProjectsFixtures.project_fixture()
      end)

    unique_id = TuistTestSupport.Utilities.unique_integer()

    %AlertRule{}
    |> AlertRule.changeset(%{
      project_id: Keyword.get(opts, :project_id, project.id),
      category: Keyword.get(opts, :category, :build_run_duration),
      metric: Keyword.get(opts, :metric, :p90),
      threshold_percentage: Keyword.get(opts, :threshold_percentage, 20.0),
      sample_size: Keyword.get(opts, :sample_size, 100),
      enabled: Keyword.get(opts, :enabled, true),
      slack_channel_id: Keyword.get(opts, :slack_channel_id, "C#{unique_id}"),
      slack_channel_name: Keyword.get(opts, :slack_channel_name, "test-channel-#{unique_id}"),
      last_triggered_at: Keyword.get(opts, :last_triggered_at, nil)
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end
end
