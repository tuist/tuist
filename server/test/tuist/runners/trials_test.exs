defmodule Tuist.Runners.TrialsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Repo
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.Trials
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(Billing, :sync_runner_subscription_items, fn _account -> {:ok, :unchanged} end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{account: user.account}
  end

  defp runner_session_fixture(account) do
    Repo.insert!(%RunnerSession{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "fleet-a",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      started_at: DateTime.utc_now(),
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    })
  end

  describe "on_trial?/1" do
    test "an account that never started one is not on trial", %{account: account} do
      refute Trials.on_trial?(account)
    end

    test "an account is on trial from the moment it starts until it is cancelled", %{account: account} do
      {:ok, account} = Trials.start(account)
      assert Trials.on_trial?(account)

      {:ok, account} = Trials.cancel(account)
      refute Trials.on_trial?(account)
    end

    test "a trial has no end date of its own, so it does not lapse", %{account: account} do
      {:ok, account} = Trials.start(account)

      assert account.runner_trial_started_at
      assert is_nil(account.runner_trial_ended_at)
    end
  end

  describe "start/1" do
    test "takes the runner items off the account's subscription", %{account: account} do
      expect(Billing, :sync_runner_subscription_items, fn synced ->
        assert Trials.on_trial?(synced)
        {:ok, :unchanged}
      end)

      assert {:ok, _account} = Trials.start(account)
    end

    test "can restart a trial that was previously cancelled", %{account: account} do
      {:ok, account} = Trials.start(account)
      {:ok, account} = Trials.cancel(account)
      refute Trials.on_trial?(account)

      assert {:ok, account} = Trials.start(account)
      assert Trials.on_trial?(account)
      assert is_nil(account.runner_trial_ended_at)
    end
  end

  describe "cancel/1" do
    test "puts the runner items back so usage becomes billable", %{account: account} do
      {:ok, account} = Trials.start(account)

      expect(Billing, :sync_runner_subscription_items, fn synced ->
        refute Trials.on_trial?(synced)
        {:ok, :unchanged}
      end)

      assert {:ok, _account} = Trials.cancel(account)
    end

    test "refuses to cancel an account that is not on a trial", %{account: account} do
      reject(&Billing.sync_runner_subscription_items/1)

      assert {:error, :not_on_trial} = Trials.cancel(account)
    end
  end

  describe "list_accounts_on_trial/0" do
    test "lists only accounts whose trial is still running", %{account: account} do
      other = AccountsFixtures.user_fixture(preload: [:account]).account
      cancelled = AccountsFixtures.user_fixture(preload: [:account]).account

      {:ok, _} = Trials.start(account)
      {:ok, started} = Trials.start(cancelled)
      {:ok, _} = Trials.cancel(started)

      ids = Enum.map(Trials.list_accounts_on_trial(), & &1.id)

      assert account.id in ids
      refute other.id in ids
      refute cancelled.id in ids
    end
  end

  describe "backfill_runner_trials/0" do
    test "puts accounts that already ran runner jobs onto a trial", %{account: account} do
      never_used_runners = AccountsFixtures.user_fixture(preload: [:account]).account
      runner_session_fixture(account)

      assert Trials.backfill_runner_trials() >= 1

      {:ok, account} = Accounts.get_account_by_id(account.id)
      {:ok, never_used_runners} = Accounts.get_account_by_id(never_used_runners.id)

      assert Trials.on_trial?(account)
      refute Trials.on_trial?(never_used_runners)
    end

    test "puts accounts that can use runners onto a trial before they run anything", %{account: account} do
      # Access is the `:runners` flag, not past usage. An account holding
      # the flag that has not run a job yet would otherwise be billed for
      # its first one the moment a Price is wired up.
      has_access = AccountsFixtures.user_fixture(preload: [:account]).account
      no_access = AccountsFixtures.user_fixture(preload: [:account]).account

      stub(FunWithFlags, :get_flag, fn :runners ->
        %FunWithFlags.Flag{
          name: :runners,
          gates: [
            %FunWithFlags.Gate{type: :actor, for: "account:#{has_access.id}", enabled: true},
            %FunWithFlags.Gate{type: :actor, for: "account:#{no_access.id}", enabled: false}
          ]
        }
      end)

      Trials.backfill_runner_trials()

      {:ok, has_access} = Accounts.get_account_by_id(has_access.id)
      {:ok, no_access} = Accounts.get_account_by_id(no_access.id)
      {:ok, account} = Accounts.get_account_by_id(account.id)

      assert Trials.on_trial?(has_access)
      # A gate that is explicitly off is not access.
      refute Trials.on_trial?(no_access)
      refute Trials.on_trial?(account)
    end

    test "never restarts a trial someone deliberately cancelled", %{account: account} do
      runner_session_fixture(account)

      {:ok, account} = Trials.start(account)
      {:ok, cancelled} = Trials.cancel(account)

      Trials.backfill_runner_trials()

      {:ok, reloaded} = Accounts.get_account_by_id(cancelled.id)
      refute Trials.on_trial?(reloaded)
    end

    test "is idempotent, so it can be re-run right before a Price is wired", %{account: account} do
      runner_session_fixture(account)

      assert Trials.backfill_runner_trials() >= 1
      {:ok, first} = Accounts.get_account_by_id(account.id)

      assert Trials.backfill_runner_trials() == 0
      {:ok, second} = Accounts.get_account_by_id(account.id)

      assert first.runner_trial_started_at == second.runner_trial_started_at
    end
  end
end
