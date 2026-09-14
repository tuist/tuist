defmodule Tuist.Accounts.Workers.UpdateAccountUsageWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Workers.UpdateAccountUsageWorker
  alias Tuist.Billing.AirUsageNotification
  alias Tuist.Billing.Workers.AirUsageNotificationWorker
  alias Tuist.Time
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account}
  end

  describe "perform/1" do
    test "queues Air emails after refreshing usage", %{account: account} do
      now = DateTime.utc_now()
      stub(Time, :utc_now, fn -> now end)

      expect(Accounts, :account_month_usage, fn id, ^now ->
        assert id == account.id
        %{remote_cache_hits_count: 160}
      end)

      assert :ok = perform_job(UpdateAccountUsageWorker, %{account_id: account.id, updated_at: now})
      assert Repo.reload!(account).current_month_remote_cache_hits_count == 160
      assert_enqueued(worker: AirUsageNotificationWorker)
    end

    test "delayed refreshes use the execution month for counts and notifications", %{account: account} do
      scheduled_at = ~U[2026-08-31 23:55:00Z]
      executed_at = ~U[2026-09-01 00:05:00Z]
      stub(Time, :utc_now, fn -> executed_at end)
      stub(DateTime, :utc_now, fn -> executed_at end)

      expect(Accounts, :account_month_usage, fn id, ^executed_at ->
        assert id == account.id
        %{remote_cache_hits_count: 160}
      end)

      assert :ok = perform_job(UpdateAccountUsageWorker, %{account_id: account.id, updated_at: scheduled_at})
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2026-09-01 00:05:00]
      assert [%{period_start: ~U[2026-09-01 00:00:00Z]}] = Repo.all(AirUsageNotification)
      assert_enqueued(worker: AirUsageNotificationWorker)
    end

    test "updates the current month usage for the account", %{project: project, account: account} do
      # Given
      updated_at = ~U[2025-04-18 15:55:00Z]
      stub(Time, :utc_now, fn -> updated_at end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: ["foo", "bar"],
        remote_test_target_hits: [],
        # Earlier in the same month
        created_at: ~U[2025-04-15 10:00:00Z]
      )

      # When
      Oban.Testing.with_testing_mode(:inline, fn ->
        {:ok, _} =
          %{account_id: account.id, updated_at: updated_at}
          |> UpdateAccountUsageWorker.new()
          |> Oban.insert()
      end)

      # # Then
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 15:55:00Z]
    end
  end
end
