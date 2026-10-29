defmodule Tuist.Sandboxes.ConcurrencyTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  test "CPU and RAM independently reject starts before placement and do not insert failed rows" do
    for limits <- [
          %{sandbox_vcpus_limit: 2, sandbox_memory_gb_limit: 64},
          %{sandbox_vcpus_limit: 32, sandbox_memory_gb_limit: 4}
        ] do
      account = account_fixture()
      {:ok, _} = Concurrency.update_limits(account, limits)
      sandbox_fixture(account: account)
      reject(Capacity, :place, 1)
      assert {:error, :sandbox_concurrency_limit} = Sandboxes.create_sandbox(account)
      assert length(Sandboxes.list_sandboxes(account)) == 1
    end
  end

  test "in-flight starts reserve quota on different nodes; paused and failed starts release it" do
    account = account_fixture()
    {:ok, _} = Concurrency.update_limits(account, %{sandbox_vcpus_limit: 4, sandbox_memory_gb_limit: 8})
    creating = sandbox_fixture(account: account, state: :creating)
    resuming = sandbox_fixture(account: account, state: :resuming)
    assert {:error, :sandbox_concurrency_limit} = Sandboxes.create_sandbox(account)
    Repo.update!(Sandbox.update_changeset(creating, %{state: :paused}))
    assert Concurrency.usage(account.id) == %{vcpus: 2, memory_mb: 4096}

    expect(Capacity, :place, fn sandbox ->
      assert Concurrency.usage(account.id) == %{vcpus: 4, memory_mb: 8192}
      assert sandbox.state == :creating
      {:error, :no_capacity}
    end)

    assert {:error, :no_capacity} = Sandboxes.create_sandbox(account)
    assert Concurrency.usage(account.id) == %{vcpus: 2, memory_mb: 4096}
    Repo.update!(Sandbox.update_changeset(resuming, %{state: :running}))
    assert Concurrency.usage(account.id) == %{vcpus: 2, memory_mb: 4096}
  end

  test "resume checks quota and reserves it before issuing a node command" do
    account = account_fixture()
    {:ok, _} = Concurrency.update_limits(account, %{sandbox_vcpus_limit: 2, sandbox_memory_gb_limit: 4})
    running = sandbox_fixture(account: account)
    paused = sandbox_fixture(account: account, state: :paused)
    stub(Nodes, :await_lookup, fn _ -> {:error, :not_connected} end)
    assert {:error, :sandbox_concurrency_limit} = Capacity.admit(paused)
    assert Repo.reload!(paused).state == :paused
    Repo.update!(Sandbox.update_changeset(running, %{state: :paused}))
    assert {:ok, %{state: :resuming}} = Capacity.admit(paused)
    assert Concurrency.usage(account.id) == %{vcpus: 2, memory_mb: 4096}
  end

  test "limits are independent of other accounts and cannot be changed in account settings" do
    account = account_fixture()
    sandbox_fixture(account: account_fixture(), vcpus: 8, memory_mb: 16_384)
    assert Concurrency.usage(account.id) == %{vcpus: 0, memory_mb: 0}
    changeset = Account.update_changeset(account, %{sandbox_vcpus_limit: 999, sandbox_memory_gb_limit: 999})
    refute Map.has_key?(changeset.changes, :sandbox_vcpus_limit)
    refute Map.has_key?(changeset.changes, :sandbox_memory_gb_limit)
  end

  test "poller leaves new and paused work queued when the account has no compute budget" do
    account = account_fixture()
    {:ok, _} = Concurrency.update_limits(account, %{sandbox_vcpus_limit: 2, sandbox_memory_gb_limit: 4})
    environment = agent_environment_fixture(account: account)
    sandbox_fixture(account: account)

    sandbox_fixture(
      account: account,
      agent_environment_id: environment.id,
      anthropic_session_id: "paused-session",
      state: :paused
    )

    refute Capacity.admissible?(environment, "new-session")
    refute Capacity.admissible?(environment, "paused-session")
  end

  test "lowering limits does not interrupt running work and blocks new work" do
    account = account_fixture()
    running = sandbox_fixture(account: account, vcpus: 8, memory_mb: 16_384)
    {:ok, _} = Concurrency.update_limits(account, %{sandbox_vcpus_limit: 2, sandbox_memory_gb_limit: 4})
    assert Repo.reload!(running).state == :running
    assert {:error, :sandbox_concurrency_limit} = Sandboxes.create_sandbox(account)
  end
end
