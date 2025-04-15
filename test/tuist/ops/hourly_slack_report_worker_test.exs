defmodule Tuist.Ops.HourlySlackReportWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias Tuist.Slack
  alias Tuist.Ops.HourlySlackReportWorker
  use Mimic

  describe "perform/0" do
    test "sends a message when there are new users and/or organizations" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: user)

      expected_message = [
        %{
          type: "section",
          text: %{
            type: "plain_text",
            text: ~s"""
            The following organizations and users have been created:
            • Organization: #{organization.account.name}
            • User: #{user.account.name} - #{user.email}
            """
          }
        }
      ]

      Slack |> expect(:send_message, fn ^expected_message -> :ok end)

      # When
      {:ok, _} = HourlySlackReportWorker.new(%{}) |> Oban.insert()
    end

    test "doesn't send a message when there were no new users or organizations in the last hour" do
      # Given
      Mimic.reject(&Slack.send_message/1)

      # When
      {:ok, _} = HourlySlackReportWorker.new(%{}) |> Oban.insert()
    end
  end
end
