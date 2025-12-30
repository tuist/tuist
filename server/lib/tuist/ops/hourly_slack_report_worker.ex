defmodule Tuist.Ops.HourlySlackReportWorker do
  @moduledoc """
  A worker that notifies us in Slack about the new organizations and users created in the last hour.
  """
  use Oban.Worker

  alias Tuist.Accounts
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Slack

  @impl Oban.Worker
  def perform(_job) do
    organizations_and_users =
      Accounts.new_organizations_in_last_hour() ++ Accounts.new_users_in_last_hour()

    if length(organizations_and_users) != 0 do
      bullet_list =
        Enum.map_join(organizations_and_users, "\n", fn
          %Organization{account: account} ->
            "• Organization: #{account.name}"

          %User{account: account} = user ->
            "• User: #{account.name} - #{user.email}"
        end)

      Slack.send_message([
        %{
          type: "section",
          text: %{
            type: "plain_text",
            text: ~s"""
            The following organizations and users have been created in #{Tuist.Environment.env()}:
            #{bullet_list}
            """
          }
        }
      ])
    end
  end
end
