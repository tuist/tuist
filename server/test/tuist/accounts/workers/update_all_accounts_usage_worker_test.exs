defmodule Tuist.Accounts.Workers.UpdateAllAccountsUsageWorkerTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts.Workers.UpdateAllAccountsUsageWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account}
  end

  describe "when there are no events this month" do
    test "current_month_remote_cache_hits_count_updated_at is updated and current_month_remote_cache_hits_count is 0",
         %{project: project, account: account} do
      # Given
      now = NaiveDateTime.utc_now(:second)
      stub(NaiveDateTime, :utc_now, fn -> now end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_hits_count: 1,
        remote_test_hits_count: 2,
        created_at: now |> Timex.beginning_of_month() |> Timex.shift(months: -1)
      )

      # When
      %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()

      # Then
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 0

      # Allow for slight timing differences (within 5 seconds)
      time_diff =
        NaiveDateTime.diff(account.current_month_remote_cache_hits_count_updated_at, now, :second)

      assert abs(time_diff) <= 5
    end
  end

  describe "when there are events with remote_cache_target_hits" do
    test "current_month_remote_cache_hits_count_updated_at is updated and current_month_remote_cache_hits_count is 1",
         %{project: project, account: account} do
      # Given
      now = ~U[2025-04-18 16:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: ["foo", "bar"],
        remote_test_target_hits: [],
        created_at: ~U[2025-04-17 16:00:00Z]
      )

      # When
      %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()

      # Then
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1

      assert account.current_month_remote_cache_hits_count_updated_at ==
               ~N[2025-04-18 16:00:00]
    end

    test "paginates through all the accounts updating their current_month_remote_cache_hits_count_updated_at and current_month_remote_cache_hits_count_columns",
         %{project: project, account: account} do
      # Given
      now = ~U[2025-04-18 16:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      %{account: another_account} = AccountsFixtures.user_fixture(preload: [:account])

      another_project = ProjectsFixtures.project_fixture(account_id: another_account.id)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: ["foo", "bar"],
        remote_test_target_hits: [],
        created_at: ~U[2025-04-17 16:00:00Z]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: another_project.id,
        remote_cache_target_hits: ["foo", "bar"],
        remote_test_target_hits: [],
        created_at: ~U[2025-04-17 16:00:00Z]
      )

      # When
      %{page_size: 1} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()

      # Then
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1

      assert account.current_month_remote_cache_hits_count_updated_at ==
               ~N[2025-04-18 16:00:00]

      another_account = Repo.reload!(another_account)
      assert another_account.current_month_remote_cache_hits_count == 1

      assert another_account.current_month_remote_cache_hits_count_updated_at ==
               ~N[2025-04-18 16:00:00]
    end
  end

  describe "when there are events with remote_test_target_hits" do
    test "current_month_remote_cache_hits_count_updated_at is updated and current_month_remote_cache_hits_count is 1",
         %{project: project, account: account} do
      # Given
      now = ~U[2025-04-18 16:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: [],
        remote_test_target_hits: ["foo", "bar"],
        created_at: ~U[2025-04-17 16:00:00Z]
      )

      # When
      %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()

      # Then
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1

      assert account.current_month_remote_cache_hits_count_updated_at ==
               ~N[2025-04-18 16:00:00]
    end
  end

  describe "when the job is called more than once the same day" do
    test "it skips the account the second time",
         %{project: project, account: account} do
      # Given
      # When: 1 run
      now = ~U[2025-04-18 16:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: [],
        remote_test_target_hits: ["foo", "bar"],
        created_at: ~U[2025-04-17 16:00:00Z]
      )

      %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()

      # Then: 1 run
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1

      assert account.current_month_remote_cache_hits_count_updated_at ==
               ~N[2025-04-18 16:00:00]

      # When: 2 run
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: ["foo"],
        remote_test_target_hits: [],
        created_at: ~U[2025-04-17 16:30:00Z]
      )

      now = ~U[2025-04-18 17:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()

      # Then: 2 run
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 16:00:00]
    end
  end
end
