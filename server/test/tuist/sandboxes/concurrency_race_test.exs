defmodule Tuist.Sandboxes.ConcurrencyRaceTest do
  use ExUnit.Case, async: false

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Ecto.Adapters.SQL.Sandbox, as: SQLSandbox
  alias Tuist.Repo
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.Sandbox

  setup do
    :ok = SQLSandbox.checkout(Repo, sandbox: false)
    user = user_fixture(preload: [:account])

    on_exit(fn ->
      SQLSandbox.checkout(Repo, sandbox: false)
      Repo.delete!(user.account)
      Repo.delete!(user)
      SQLSandbox.checkin(Repo)
    end)

    {:ok, account: user.account}
  end

  test "uncommitted creation excludes a simultaneous resume on another node", %{account: account} do
    {:ok, account} = Concurrency.update_limits(account, %{sandbox_vcpus_limit: 2, sandbox_memory_gb_limit: 4})
    paused = sandbox_fixture(account: account, state: :paused)
    parent = self()

    task =
      Task.async(fn ->
        :ok = SQLSandbox.checkout(Repo, sandbox: false)

        try do
          Concurrency.admit(account.id, %{vcpus: 2, memory_mb: 4096}, fn ->
            created = sandbox_fixture(account: account, state: :creating)
            send(parent, :reservation_held)

            receive do
              :commit -> {:ok, created}
            after
              5_000 -> raise "test did not release admission transaction"
            end
          end)
        after
          SQLSandbox.checkin(Repo)
        end
      end)

    try do
      assert_receive :reservation_held, 5_000
      reserve_resume = fn -> paused |> Sandbox.update_changeset(%{state: :resuming}) |> Repo.update() end
      assert {:error, :sandbox_account_busy} = Concurrency.admit(account.id, paused, reserve_resume)
      send(task.pid, :commit)
      assert {:ok, _} = Task.await(task)
      assert {:error, :sandbox_concurrency_limit} = Concurrency.admit(account.id, paused, reserve_resume)
      assert Repo.reload!(paused).state == :paused
      assert Concurrency.usage(account.id) == %{vcpus: 2, memory_mb: 4096}
    after
      send(task.pid, :commit)
      Task.shutdown(task)
    end
  end
end
