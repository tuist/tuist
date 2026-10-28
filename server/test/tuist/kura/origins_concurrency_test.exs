defmodule Tuist.Kura.OriginsConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Kura.OriginRollup
  alias Tuist.Kura.Origins
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    users = [AccountsFixtures.user_fixture(), AccountsFixtures.user_fixture()]
    account_ids = Enum.map(users, & &1.account.id)
    user_ids = Enum.map(users, & &1.id)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        Repo.delete_all(from(account in Account, where: account.id in ^account_ids))
        Repo.delete_all(from(user in User, where: user.id in ^user_ids))
      after
        Sandbox.checkin(Repo)
      end
    end)

    %{account: hd(users).account, deleted_account: List.last(users).account}
  end

  test "a deletion committing during the write does not discard surviving accounts", %{
    account: account,
    deleted_account: deleted_account
  } do
    parent = self()

    deletion =
      database_task(fn ->
        Repo.transaction(fn ->
          Repo.delete!(deleted_account)
          send(parent, :account_deleted)

          receive do
            :commit -> :deleted
          after
            10_000 -> Repo.rollback(:commit_timeout)
          end
        end)
      end)

    try do
      assert_receive :account_deleted, 5_000

      flush =
        database_task(fn ->
          %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
          send(parent, {:flush_started, backend_pid})

          Origins.upsert_many(
            Enum.map([deleted_account, account], fn account ->
              %{account_id: account.id, origin: "FR", date: Date.utc_today(), run_count: 3, demand_count: 2}
            end)
          )
        end)

      try do
        assert_receive {:flush_started, backend_pid}, 5_000
        assert wait_until_blocked(backend_pid, 500)
        send(deletion.pid, :commit)

        assert {:ok, :deleted} = Task.await(deletion)
        assert {:ok, 1} = Task.await(flush)
        assert %OriginRollup{run_count: 3, demand_count: 2} = Repo.get_by!(OriginRollup, account_id: account.id)
        refute Repo.get_by(OriginRollup, account_id: deleted_account.id)
      after
        Task.shutdown(flush, :brutal_kill)
      end
    after
      Task.shutdown(deletion, :brutal_kill)
    end
  end

  defp database_task(function) do
    Task.async(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)

      try do
        function.()
      rescue
        error -> {:error, error}
      after
        Sandbox.checkin(Repo)
      end
    end)
  end

  defp wait_until_blocked(_backend_pid, 0), do: false

  defp wait_until_blocked(backend_pid, attempts) do
    case Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [backend_pid]) do
      %{rows: [[true]]} ->
        true

      %{rows: [[false]]} ->
        Process.sleep(10)
        wait_until_blocked(backend_pid, attempts - 1)
    end
  end
end
