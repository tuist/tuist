defmodule TuistTestSupport.Fixtures.SlackFixtures do
  @moduledoc false

  alias Tuist.Repo
  alias Tuist.Slack.Alert
  alias Tuist.Slack.Installation
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  def slack_installation_fixture(opts \\ []) do
    account =
      opts
      |> Keyword.get_lazy(:account, fn ->
        AccountsFixtures.user_fixture()
      end)
      |> Repo.preload([:account])

    unique_id = TuistTestSupport.Utilities.unique_integer()

    %Installation{}
    |> Installation.changeset(%{
      account_id: Keyword.get(opts, :account_id, account.account.id),
      team_id: Keyword.get(opts, :team_id, "T#{unique_id}"),
      team_name: Keyword.get(opts, :team_name, "Test Workspace #{unique_id}"),
      access_token: Keyword.get(opts, :access_token, "xoxb-test-token-#{unique_id}"),
      bot_user_id: Keyword.get(opts, :bot_user_id, "U#{unique_id}")
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end

  def slack_alert_fixture(opts \\ []) do
    project =
      Keyword.get_lazy(opts, :project, fn ->
        ProjectsFixtures.project_fixture()
      end)

    unique_id = TuistTestSupport.Utilities.unique_integer()

    %Alert{}
    |> Alert.changeset(%{
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
