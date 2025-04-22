defmodule Tuist.Accounts.Workers.UpdateAccountUsageWorkerTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts.Workers.UpdateAccountUsageWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = %{account: account} = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: account.id)
    %{user: user, project: project, account: account}
  end

  describe "perform/1" do
    test "updates the current month usage for the account", %{project: project, account: account} do
      # Given
      now = ~U[2025-04-18 15:55:00Z]
      stub(DateTime, :utc_now, fn -> now end)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: ["foo", "bar"],
        remote_test_target_hits: [],
        created_at: ~U[2025-04-18 15:54:00Z]
      )

      # When
      {:ok, _} = %{account_id: account.id} |> UpdateAccountUsageWorker.new() |> Oban.insert()

      # # Then
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 15:55:00]
    end
  end
end
