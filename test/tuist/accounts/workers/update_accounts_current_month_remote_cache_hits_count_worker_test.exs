defmodule Tuist.Accounts.Workers.UpdateAccountsCurrentMonthRemoteCacheHitsCountWorkerTest do
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias Tuist.Accounts.Workers.UpdateAccountsCurrentMonthRemoteCacheHitsCountWorker
  use TuistTestSupport.Cases.DataCase
  use Mimic

  setup do
    user = %{account: user_account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user_account.id)
    %{user: user, project: project, user_account: user_account}
  end

  describe "when there are no events this month" do
    test "current_month_remote_cache_hits_count_updated_at is updated and current_month_remote_cache_hits_count is 0",
         %{project: project, user_account: user_account} do
      # Given
      now = NaiveDateTime.utc_now(:second)
      Tuist.Time |> stub(:naive_utc_now, fn -> now end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits_count: 1,
        remote_test_target_hits_count: 2,
        created_at: now |> Timex.beginning_of_month() |> Timex.shift(months: -1)
      )

      # When
      UpdateAccountsCurrentMonthRemoteCacheHitsCountWorker.perform(%{})

      # Then
      user_account = user_account |> Repo.reload!()
      assert user_account.current_month_remote_cache_hits_count == 0
      assert user_account.current_month_remote_cache_hits_count_updated_at == now
    end
  end

  describe "when there are events with remote_cache_target_hits" do
    test "current_month_remote_cache_hits_count_updated_at is updated and current_month_remote_cache_hits_count is 1",
         %{project: project, user_account: user_account} do
      # Given
      date = NaiveDateTime.utc_now(:second) |> Timex.end_of_month() |> Timex.shift(days: -1)
      Tuist.Time |> stub(:naive_utc_now, fn -> date end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: ["foo", "bar"],
        remote_test_target_hits: [],
        created_at: date |> Timex.beginning_of_month() |> Timex.shift(days: 1)
      )

      # When
      UpdateAccountsCurrentMonthRemoteCacheHitsCountWorker.perform(%{})

      # Then
      user_account = user_account |> Repo.reload!()
      assert user_account.current_month_remote_cache_hits_count == 1
      assert user_account.current_month_remote_cache_hits_count_updated_at == date
    end
  end

  describe "when there are events with remote_test_target_hits" do
    test "current_month_remote_cache_hits_count_updated_at is updated and current_month_remote_cache_hits_count is 1",
         %{project: project, user_account: user_account} do
      # Given
      date = NaiveDateTime.utc_now(:second) |> Timex.end_of_month() |> Timex.shift(days: -1)
      Tuist.Time |> stub(:naive_utc_now, fn -> date end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: [],
        remote_test_target_hits: ["foo", "bar"],
        created_at: date |> Timex.beginning_of_month() |> Timex.shift(days: 1)
      )

      # When
      UpdateAccountsCurrentMonthRemoteCacheHitsCountWorker.perform(%{})

      # Then
      user_account = user_account |> Repo.reload!()
      assert user_account.current_month_remote_cache_hits_count == 1
      assert user_account.current_month_remote_cache_hits_count_updated_at == date
    end
  end

  describe "when the job is called more than once the same day" do
    test "it skips the account the second time",
         %{project: project, user_account: user_account} do
      # Given
      date =
        NaiveDateTime.utc_now(:second)
        |> Timex.end_of_month()
        |> Timex.beginning_of_day()
        |> Timex.shift(hours: 1)
        |> Timex.shift(days: -1)
        |> NaiveDateTime.truncate(:second)

      date_one_hour_later = date |> Timex.shift(hours: 1)

      # When: 1 run
      Tuist.Time |> stub(:naive_utc_now, fn -> date end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: [],
        remote_test_target_hits: ["foo", "bar"],
        created_at: date |> Timex.beginning_of_month() |> Timex.shift(days: 1)
      )

      UpdateAccountsCurrentMonthRemoteCacheHitsCountWorker.perform(%{})

      # Then: 1 run
      user_account = user_account |> Repo.reload!()
      assert user_account.current_month_remote_cache_hits_count == 1
      assert user_account.current_month_remote_cache_hits_count_updated_at == date

      # When: 2 run
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: ["foo"],
        remote_test_target_hits: [],
        created_at: date |> Timex.beginning_of_month() |> Timex.shift(days: 1)
      )

      Tuist.Time |> stub(:naive_utc_now, fn -> date_one_hour_later end)

      UpdateAccountsCurrentMonthRemoteCacheHitsCountWorker.perform(%{})

      # Then: 2 run
      user_account = user_account |> Repo.reload!()
      assert user_account.current_month_remote_cache_hits_count == 1
      assert user_account.current_month_remote_cache_hits_count_updated_at == date
    end
  end
end
