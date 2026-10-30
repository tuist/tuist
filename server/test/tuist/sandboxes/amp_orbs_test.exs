defmodule Tuist.Sandboxes.AmpOrbsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpOrbs
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  setup do
    account = account_fixture()
    stub(Capacity, :admit_turn, fn _sandbox, fun -> fun.() end)
    %{account: account}
  end

  defp spawn_params, do: %{operation: "spawn", orb_token: "orb-secret"}

  test "creates once and bootstraps repeated spawn with a protected residency", %{account: account} do
    expect(Capacity, :place, fn _ -> {:ok, "node-a"} end)
    expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

    expect(Nodes, :call, 2, fn "node-a", "exec", args, _opts ->
      assert args.cmd == ["/usr/local/bin/sbx-orb-bootstrap"]
      assert args.env == %{"ORB_TOKEN" => "orb-secret", "AMP_URL" => "https://ampcode.com"}
      assert Repo.get!(Sandbox, args.sandbox_id).residency_work_id == "amp:amp-thread"
      assert {:ok, :skipped} = Sandboxes.pause_idle(args.sandbox_id)
      {:ok, %{"exit_code" => 0}}
    end)

    assert {:ok, first} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert {:ok, second} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert first.id == second.id
    assert [%{amp_orb_id: "amp-thread"}] = Sandboxes.list_sandboxes(account)
  end

  test "resume uses the existing disk and passes a fresh token and custom URL", %{account: account} do
    sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", state: :paused, node_name: "node-a")
    expect(Capacity, :admit, fn actual -> {:ok, actual} end)

    expect(Nodes, :call, fn "node-a", "resume", %{sandbox_id: id}, _opts ->
      assert id == sandbox.id
      {:ok, %{}}
    end)

    expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
      assert env == %{"ORB_TOKEN" => "fresh-token", "AMP_URL" => "https://amp.example.com"}
      {:ok, %{"exit_code" => 0}}
    end)

    assert {:ok, %{id: id, state: :running}} =
             AmpOrbs.dispatch(account, "amp-thread", %{
               operation: "spawn",
               orb_token: "fresh-token",
               amp_url: "https://amp.example.com"
             })

    assert id == sandbox.id
  end

  test "pause is repeatable and only releases residency after a successful snapshot", %{account: account} do
    sandbox =
      sandbox_fixture(
        account: account,
        amp_orb_id: "amp-thread",
        node_name: "node-a",
        residency_work_id: "amp:amp-thread"
      )

    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:error, :timeout} end)
    assert {:error, :timeout} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})
    assert Repo.reload!(sandbox).residency_work_id == "amp:amp-thread"

    expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

    assert {:ok, %{state: :paused, residency_work_id: nil}} =
             AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})

    assert {:ok, %{state: :paused}} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})
  end

  test "delete is repeatable and lookup is account-scoped", %{account: account} do
    sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")
    other = account_fixture()
    assert {:ok, nil} = AmpOrbs.dispatch(other, "amp-thread", %{operation: "delete"})
    assert {:ok, nil} = AmpOrbs.dispatch(other, "amp-thread", %{operation: "pause"})
    assert Repo.reload!(sandbox)
    expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)
    assert {:ok, nil} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "delete"})
    assert {:ok, nil} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "delete"})
    refute Repo.get(Sandbox, sandbox.id)
  end

  test "bootstrap failure drops the residency and never returns guest output", %{account: account} do
    sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")

    expect(Nodes, :call, fn "node-a", "exec", _args, opts ->
      opts[:on_stream].({"stderr", Base.encode64("orb-secret")})
      {:ok, %{"exit_code" => 1}}
    end)

    assert {:error, :orb_bootstrap_failed} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert Repo.reload!(sandbox).residency_work_id == nil
  end

  test "CI admission refusal never starts bootstrap", %{account: account} do
    sandbox_fixture(account: account, amp_orb_id: "amp-thread", node_name: "node-a")
    expect(Capacity, :admit_turn, fn _sandbox, _fun -> {:error, :no_capacity} end)
    reject(&Nodes.call/4)
    assert {:error, :no_capacity} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
  end

  test "a placed errored Orb retains its disk instead of being recreated", %{account: account} do
    sandbox = sandbox_fixture(account: account, amp_orb_id: "amp-thread", state: :error)
    reject(&Nodes.call/4)
    assert {:error, {:invalid_state, :error}} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert Repo.reload!(sandbox)
  end

  test "overlapping dispatch receives a bounded conflict without touching the VM", %{account: account} do
    parent = self()

    task =
      Task.async(fn ->
        Sandboxes.with_sandbox_lock("amp:#{account.id}:amp-thread", fn ->
          send(parent, :locked)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :locked
    reject(&Nodes.call/4)
    assert {:error, :locked} = AmpOrbs.dispatch(account, "amp-thread", %{operation: "pause"})
    send(task.pid, :release)
    Task.await(task)
  end

  test "retries failed placement without a node instead of stranding the Orb identity", %{account: account} do
    expect(Capacity, :place, fn _ -> {:error, :no_capacity} end)
    assert {:error, :no_capacity} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert %{state: :error, node_name: nil} = Repo.get_by!(Sandbox, account_id: account.id, amp_orb_id: "amp-thread")

    expect(Capacity, :place, fn _ -> {:ok, "node-a"} end)
    expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)
    expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)
    assert {:ok, %{state: :running}} = AmpOrbs.dispatch(account, "amp-thread", spawn_params())
    assert length(Sandboxes.list_sandboxes(account)) == 1
  end

  test "database identity is unique within an account and independent across accounts", %{account: account} do
    sandbox_fixture(account: account, amp_orb_id: "amp-thread")
    other = account_fixture()
    assert sandbox_fixture(account: other, amp_orb_id: "amp-thread")

    attrs = %{
      account_id: account.id,
      amp_orb_id: "amp-thread",
      template: "default",
      vcpus: 2,
      memory_mb: 4096,
      workspace_gb: 10
    }

    assert {:error, changeset} = %Sandbox{} |> Sandbox.create_changeset(attrs) |> Repo.insert()
    assert %{account_id: ["has already been taken"]} = errors_on(changeset)
  end
end
