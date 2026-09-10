defmodule Tuist.Ops.HourlySlackReportWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Ops.HourlySlackReportWorker
  alias Tuist.Slack
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "perform/1" do
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
            The following organizations and users have been created in test:
            • Organization: #{organization.account.name}
            • User: #{user.account.name} - #{user.email}
            """
          }
        }
      ]

      expect(Slack, :send_message, fn ^expected_message, [channel: "#gtm"] -> :ok end)

      # When
      Oban.Testing.with_testing_mode(:inline, fn ->
        {:ok, _} = %{} |> HourlySlackReportWorker.new() |> Oban.insert()
      end)
    end

    test "doesn't send a message when there were no new users or organizations in the last hour" do
      # Given
      Mimic.reject(&Slack.send_message/2)

      # When
      Oban.Testing.with_testing_mode(:inline, fn ->
        {:ok, _} = %{} |> HourlySlackReportWorker.new() |> Oban.insert()
      end)
    end

    test "returns delivery errors so Oban retries the report" do
      AccountsFixtures.user_fixture()

      expect(Slack, :send_message, fn _, [channel: "#gtm"] ->
        {:error, "Slack API error: not_in_channel"}
      end)

      assert {:error, "Slack API error: not_in_channel"} =
               perform_job(HourlySlackReportWorker, %{})
    end
  end
end
