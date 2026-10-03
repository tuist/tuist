defmodule Tuist.Ops.HourlySlackReportWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.Ops.HourlySlackReportWorker
  alias Tuist.Slack
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "perform/1" do
    test "reports the completed UTC hour even when cron insertion is slightly late" do
      user = AccountsFixtures.user_fixture(created_at: ~U[2026-09-10 19:15:00Z])
      organization = AccountsFixtures.organization_fixture(creator: user, created_at: ~U[2026-09-10 19:30:00Z])
      AccountsFixtures.user_fixture(created_at: ~U[2026-09-10 20:00:00Z])

      expected_message = [
        %{
          type: "section",
          text: %{
            type: "plain_text",
            text: """
            The following organizations and users have been created in test:
            2026-09-10 19:00 – 2026-09-10 20:00 UTC
            • Organization: #{organization.account.name}
            • User: #{user.account.name} - #{user.email}
            """
          }
        }
      ]

      expect(Slack, :send_message, fn ^expected_message, [channel: "#gtm"] -> :ok end)

      assert :ok =
               perform_job(HourlySlackReportWorker, %{}, inserted_at: ~U[2026-09-10 20:00:00.652089Z])
    end

    test "returns ok without sending when the original reporting hour is empty" do
      AccountsFixtures.user_fixture(created_at: ~U[2026-09-10 20:05:00Z])
      Mimic.reject(&Slack.send_message/2)

      assert :ok =
               perform_job(HourlySlackReportWorker, %{},
                 inserted_at: ~U[2026-09-10 19:00:00Z],
                 scheduled_at: ~U[2026-09-10 20:15:00Z],
                 attempt: 12
               )
    end

    test "a delayed retry retains its original accounts and does not overlap the next hour's report" do
      earlier = AccountsFixtures.user_fixture(created_at: ~U[2026-09-10 18:30:00Z])
      newer = AccountsFixtures.user_fixture(created_at: ~U[2026-09-10 20:05:00Z])

      expect(Slack, :send_message, fn [%{text: %{text: text}}], [channel: "#gtm"] ->
        assert text =~ earlier.email
        refute text =~ newer.email
        {:error, "Slack API error: invalid_blocks"}
      end)

      assert {:error, "Slack API error: invalid_blocks"} =
               perform_job(HourlySlackReportWorker, %{}, inserted_at: ~U[2026-09-10 19:00:00.064802Z])

      expect(Slack, :send_message, fn [%{text: %{text: text}}], [channel: "#gtm"] ->
        assert text =~ "2026-09-10 18:00 – 2026-09-10 19:00 UTC"
        assert text =~ earlier.email
        refute text =~ newer.email
        :ok
      end)

      assert :ok =
               perform_job(HourlySlackReportWorker, %{},
                 inserted_at: ~U[2026-09-10 19:00:00.064802Z],
                 scheduled_at: ~U[2026-09-10 20:15:45.380297Z],
                 attempted_at: ~U[2026-09-10 20:15:46Z],
                 attempt: 12
               )

      expect(Slack, :send_message, fn [%{text: %{text: text}}], [channel: "#gtm"] ->
        assert text =~ newer.email
        refute text =~ earlier.email
        :ok
      end)

      assert :ok = perform_job(HourlySlackReportWorker, %{}, inserted_at: ~U[2026-09-10 21:00:00.659457Z])
    end

    test "bounds large reports and long account lines below Slack's section limit" do
      organizations = List.duplicate(%Organization{account: %Account{name: String.duplicate("o", 300)}}, 10)

      users =
        List.duplicate(%User{account: %Account{name: String.duplicate("u", 300)}, email: "signup@example.com"}, 10_000)

      stub(Accounts, :new_organizations_in_period, fn _, _ -> organizations end)
      stub(Accounts, :new_users_in_period, fn _, _ -> users end)

      expect(Slack, :send_message, fn [%{text: %{text: text}}], [channel: "#gtm"] ->
        assert String.length(text) <= 3000
        assert length(Regex.scan(~r/^• /m, text)) == 20
        assert text =~ "9990 more accounts not shown."
        assert text =~ "• Organization: "
        assert text =~ "• User: "
        :ok
      end)

      assert :ok = perform_job(HourlySlackReportWorker, %{}, inserted_at: ~U[2026-09-10 20:00:00Z])
    end
  end
end
