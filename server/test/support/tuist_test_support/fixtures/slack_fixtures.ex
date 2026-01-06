defmodule TuistTestSupport.Fixtures.SlackFixtures do
  @moduledoc false

  alias Tuist.Repo
  alias Tuist.Slack.Installation
  alias TuistTestSupport.Fixtures.AccountsFixtures

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
end
