defmodule Tuist.Ops.HourlySlackReportWorker do
  @moduledoc """
  Reports new organizations and users to #gtm for the UTC hour preceding job insertion.
  Retries retain the original window, and large reports include a bounded preview.
  """
  use Oban.Worker

  alias Tuist.Accounts
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Slack

  @max_accounts 20
  @max_line_length 120

  @impl Oban.Worker
  def perform(%Oban.Job{inserted_at: inserted_at}) do
    # Oban moves scheduled_at on retry; inserted_at keeps the original reporting hour.
    end_at = DateTime.from_unix!(div(DateTime.to_unix(inserted_at), 3600) * 3600)
    start_at = DateTime.add(end_at, -1, :hour)

    organizations_and_users =
      Accounts.new_organizations_in_period(start_at, end_at) ++ Accounts.new_users_in_period(start_at, end_at)

    if organizations_and_users == [] do
      :ok
    else
      bullet_list =
        organizations_and_users
        |> Enum.take(@max_accounts)
        |> Enum.map_join("\n", &account_line/1)

      omitted_count = max(length(organizations_and_users) - @max_accounts, 0)
      overflow = if omitted_count > 0, do: "\n… #{omitted_count} more accounts not shown.", else: ""

      Slack.send_message(
        [
          %{
            type: "section",
            text: %{
              type: "plain_text",
              text: ~s"""
              The following organizations and users have been created in #{Tuist.Environment.env()}:
              #{Calendar.strftime(start_at, "%Y-%m-%d %H:%M")} – #{Calendar.strftime(end_at, "%Y-%m-%d %H:%M")} UTC
              #{bullet_list}#{overflow}
              """
            }
          }
        ],
        channel: "#gtm"
      )
    end
  end

  defp account_line(account) do
    line =
      case account do
        %Organization{account: account} -> "• Organization: #{account.name}"
        %User{account: account} = user -> "• User: #{account.name} - #{user.email}"
      end

    if String.length(line) > @max_line_length do
      String.slice(line, 0, @max_line_length - 1) <> "…"
    else
      line
    end
  end
end
