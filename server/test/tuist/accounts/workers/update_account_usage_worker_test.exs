defmodule Tuist.Accounts.Workers.UpdateAccountUsageWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
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
      updated_at = ~U[2025-04-18 15:55:00Z]

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        remote_cache_target_hits: ["foo", "bar"],
        remote_test_target_hits: [],
        # Earlier in the same month
        created_at: ~U[2025-04-15 10:00:00Z]
      )

      # When
      {:ok, _} =
        %{account_id: account.id, updated_at: updated_at}
        |> UpdateAccountUsageWorker.new()
        |> Oban.insert()

      # # Then
      account = Repo.reload!(account)
      assert account.current_month_remote_cache_hits_count == 1
      assert account.current_month_remote_cache_hits_count_updated_at == ~N[2025-04-18 15:55:00Z]
    end
  end
end
