defmodule Atlas.FeatureUsage.Workers.FeatureUsageWorkersTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.FeatureUsage.Workers.RefreshAccountFeatureUsage
  alias Atlas.FeatureUsage.Workers.ScheduleFeatureUsage
  alias Atlas.Repo

  describe "ScheduleFeatureUsage" do
    test "enqueues one refresh job per tracked account" do
      insert = fn changeset -> {:ok, changeset} end

      assert {:ok, 2} =
               ScheduleFeatureUsage.perform(%Oban.Job{},
                 list_account_ids: fn -> ["a", "b"] end,
                 insert: insert
               )
    end

    test "halts when an insert fails" do
      error = %Ecto.Changeset{}

      insert = fn
        %Ecto.Changeset{changes: %{args: %{account_id: "first"}}} = cs -> {:ok, cs}
        %Ecto.Changeset{changes: %{args: %{account_id: "second"}}} -> {:error, error}
      end

      assert {:error, ^error} =
               ScheduleFeatureUsage.perform(%Oban.Job{},
                 list_account_ids: fn -> ["first", "second"] end,
                 insert: insert
               )
    end

    test "uses the real enqueue path to schedule RefreshAccountFeatureUsage for tracked accounts" do
      account =
        %Account{}
        |> Account.changeset(%{
          account_key: "account:#{System.unique_integer([:positive])}",
          name: "Acme",
          segment: :customer
        })
        |> Repo.insert!()

      %AccountHandle{}
      |> AccountHandle.changeset(%{account_id: account.id, handle: "acme", source: "tuist"})
      |> Repo.insert!()

      assert {:ok, 1} = perform_job(ScheduleFeatureUsage, %{})
      assert_enqueued(worker: RefreshAccountFeatureUsage, args: %{"account_id" => account.id})
    end
  end

  describe "RefreshAccountFeatureUsage" do
    test "returns :ok when the refresh succeeds" do
      refresh = fn account_id ->
        assert account_id == "account-123"
        {:ok, %{account: %{id: account_id}, snapshots: [], alerts: []}}
      end

      assert :ok =
               RefreshAccountFeatureUsage.perform(%Oban.Job{args: %{"account_id" => "account-123"}}, refresh: refresh)
    end

    test "cancels when the account or its handle is gone" do
      refresh = fn _account_id -> {:error, :not_found} end

      assert {:cancel, :account_not_found} =
               RefreshAccountFeatureUsage.perform(%Oban.Job{args: %{"account_id" => "gone"}}, refresh: refresh)
    end

    test "retries on a transient proxy error" do
      refresh = fn _account_id -> {:error, "Could not reach the Tuist server."} end

      assert {:error, "Could not reach the Tuist server."} =
               RefreshAccountFeatureUsage.perform(%Oban.Job{args: %{"account_id" => "acct"}}, refresh: refresh)
    end
  end
end
