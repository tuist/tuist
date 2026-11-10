defmodule Tuist.Accounts.Workers.UpdateAllAccountsUsageWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Workers.UpdateAllAccountsUsageWorker
  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    %{user: user, account: account}
  end

  describe "when there is no cache usage this month" do
    test "stamps the refresh time and stores zero usage", %{account: account} do
      # Given
      now = NaiveDateTime.utc_now(:second)
      stub(NaiveDateTime, :utc_now, fn -> now end)

      # When
      Oban.Testing.with_testing_mode(:inline, fn ->
        %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

      # Then
      account = Repo.reload!(account)
      assert account.current_month_cache_egress_megabytes == 0
      assert account.current_month_cache_requests == 0

      # Allow for slight timing differences (within 5 seconds)
      time_diff =
        NaiveDateTime.diff(account.current_month_remote_cache_hits_count_updated_at, now, :second)

      assert abs(time_diff) <= 5
    end
  end

  describe "when there is cache usage this month" do
    test "stores the metered cache usage and stamps the refresh time", %{account: account} do
      # Given
      now = ~U[2025-04-18 16:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      insert_cache_usage(account.id, requests: 300, window_start: ~N[2025-04-17 16:00:00])

      # When
      Oban.Testing.with_testing_mode(:inline, fn ->
        %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

      # Then
      account = Repo.reload!(account)
      assert account.current_month_cache_requests == 300
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 16:00:00]
    end

    test "paginates through all the accounts", %{account: account} do
      # Given
      now = ~U[2025-04-18 16:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      %{account: another_account} = AccountsFixtures.user_fixture(preload: [:account])

      insert_cache_usage(account.id, requests: 100, window_start: ~N[2025-04-17 16:00:00])
      insert_cache_usage(another_account.id, requests: 200, window_start: ~N[2025-04-17 16:00:00])

      # When
      Oban.Testing.with_testing_mode(:inline, fn ->
        %{page_size: 1} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

      # Then
      account = Repo.reload!(account)
      assert account.current_month_cache_requests == 100
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 16:00:00]

      another_account = Repo.reload!(another_account)
      assert another_account.current_month_cache_requests == 200
      assert another_account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 16:00:00]
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
      assert length(batch_sizes) > 1
    end
  end

  describe "when the job is called more than once the same day" do
    test "it skips the account the second time", %{account: account} do
      # Given
      # When: 1 run
      now = ~U[2025-04-18 16:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)
      insert_cache_usage(account.id, requests: 100, window_start: ~N[2025-04-17 16:00:00])

      Oban.Testing.with_testing_mode(:inline, fn ->
        %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

      # Then: 1 run
      account = Repo.reload!(account)
      assert account.current_month_cache_requests == 100
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 16:00:00]

      # When: 2 run
      insert_cache_usage(account.id, requests: 50, window_start: ~N[2025-04-17 16:30:00])

      now = ~U[2025-04-18 17:00:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      Oban.Testing.with_testing_mode(:inline, fn ->
        %{} |> UpdateAllAccountsUsageWorker.new() |> Oban.insert()
      end)

      # Then: 2 run
      account = Repo.reload!(account)
      assert account.current_month_cache_requests == 100
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 16:00:00]
    end
  end

  defp insert_cache_usage(account_id, opts) do
    window_start = Keyword.fetch!(opts, :window_start)

    IngestRepo.insert_all(UsageEvent, [
      %{
        event_id: "evt-#{System.unique_integer([:positive])}",
        account_id: account_id,
        project_id: 0,
        node_id: "kura-test",
        region: "eu-west",
        traffic_plane: "public",
        direction: "egress",
        operation: "download",
        protocol: "http",
        artifact_kind: "xcode",
        bytes: 1_000_000,
        request_count: Keyword.fetch!(opts, :requests),
        window_start: window_start,
        window_seconds: 60,
        inserted_at: window_start
      }
    ])
  end

  defp collect_batch_sizes(acc) do
    receive do
      {:insert_all, size} -> collect_batch_sizes([size | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
