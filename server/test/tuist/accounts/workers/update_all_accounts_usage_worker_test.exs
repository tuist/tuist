defmodule Tuist.Accounts.Workers.UpdateAllAccountsUsageWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
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
      Oban.Testing.with_testing_mode(:inline, fn ->
        %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

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
      Oban.Testing.with_testing_mode(:inline, fn ->
        %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

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
      Oban.Testing.with_testing_mode(:inline, fn ->
        %{page_size: 1} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

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
      Oban.Testing.with_testing_mode(:inline, fn ->
        %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

      # Then
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1

      assert account.current_month_remote_cache_hits_count_updated_at ==
               ~N[2025-04-18 16:00:00]
    end
  end

  describe "when there are more accounts than fit in a single insert" do
    test "inserts the account usage workers in batches that stay under the PostgreSQL parameter limit" do
      # Given
      account_count = 2_500
      accounts = Enum.map(1..account_count, fn id -> %{id: id} end)

      meta = %Flop.Meta{
        flop: %Flop{page: 1, page_size: 1_000},
        current_page: 1,
        total_pages: 1
      }

      stub(Accounts, :list_accounts_with_usage_not_updated_today, fn _attrs ->
        {accounts, meta}
      end)

      test_pid = self()

      stub(Oban, :insert_all, fn workers ->
        send(test_pid, {:insert_all, length(workers)})
        workers
      end)

      # When
      assert :ok == UpdateAllAccountsUsageWorker.perform(%{args: %{}})

      # Then
      batch_sizes = collect_batch_sizes([])

      assert Enum.sum(batch_sizes) == account_count
      assert Enum.all?(batch_sizes, &(&1 <= 1_000))
      assert length(batch_sizes) == 3
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

      Oban.Testing.with_testing_mode(:inline, fn ->
        %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

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

      Oban.Testing.with_testing_mode(:inline, fn ->
        %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

      # Then: 2 run
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 16:00:00]
    end
  end

  defp collect_batch_sizes(acc) do
    receive do
      {:insert_all, size} -> collect_batch_sizes([size | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
