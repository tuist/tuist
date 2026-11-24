defmodule Tuist.SandboxesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Runners.VolumeAffinities
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand
  alias Tuist.Sandboxes.SandboxEvent
  alias Tuist.Sandboxes.UsageEvent
  alias Tuist.Sandboxes.Workers.ArchiveSandboxesWorker
  alias Tuist.Sandboxes.Workers.PauseIdleOrbWorker
  alias Tuist.Sandboxes.Workers.PauseSandboxWorker

  defp events(%Sandbox{id: id}) do
    ClickHouseRepo.all(from(e in SandboxEvent, where: e.sandbox_id == ^id, order_by: e.inserted_at, select: e.event))
  end

  test "a thread's sandbox is left out of the account's sandbox list and lookup" do
    account = account_fixture()
    thread = Repo.insert!(%ProviderEnvironment{account_id: account.id, external_key: "threads/#{Ecto.UUID.generate()}"})
    other = Repo.insert!(%ProviderEnvironment{account_id: account.id, external_key: "orb-provider/1"})
    hidden = sandbox_fixture(account: account, provider_environment_id: thread.id)
    shown = sandbox_fixture(account: account, provider_environment_id: other.id)
    plain = sandbox_fixture(account: account)

    assert Enum.sort(Enum.map(Sandboxes.list_sandboxes(account), & &1.id)) == Enum.sort([shown.id, plain.id])
    assert Sandboxes.count_sandboxes(account) == 2
    assert Sandboxes.count_sandboxes_by_state(account).running == 2
    assert {:error, :not_found} = Sandboxes.get_sandbox(account, hidden.id)
    assert {:ok, _} = Sandboxes.get_sandbox(account, shown.id)
  end

  test "creator matching excludes organizations, disabled users and fallback labels" do
    user = user_fixture()
    disabled = user_fixture()
    disabled |> Ecto.Changeset.change(disabled_at: DateTime.utc_now(:second)) |> Repo.update!()
    %{account: organization} = organization_fixture(preload: [:account])

    sandboxes =
      for {username, name} <- [
            {organization.name, organization.name},
            {disabled.account.name, disabled.account.name},
            {nil, user.account.name}
          ] do
        sandbox_fixture()
        |> Ecto.Changeset.change(amp_creator_user_id: "user_amp", amp_creator_username: username, amp_creator_name: name)
        |> Repo.update!()
      end

    assert Enum.map(Sandboxes.preload_creators(sandboxes), & &1.creator_actor) == [
             %{name: organization.name, source: :reported},
             %{name: disabled.account.name, source: :reported},
             %{name: user.account.name, source: :reported}
           ]
  end

  test "creator email matching requires verification and prefers email over a conflicting username" do
    verified_at = DateTime.utc_now(:second)
    creator = user_fixture(email_verified_at: verified_at)
    other = user_fixture()
    unverified = user_fixture()
    disabled = user_fixture(email_verified_at: verified_at)
    disabled |> Ecto.Changeset.change(disabled_at: verified_at) |> Repo.update!()
    inactive = user_fixture(email_verified_at: verified_at)
    inactive |> Ecto.Changeset.change(active: false) |> Repo.update!()

    sandboxes =
      for {email, username, label} <- [
            {String.upcase(creator.email), other.account.name, "different-amp-name"},
            {unverified.email, nil, "unverified"},
            {disabled.email, nil, "disabled"},
            {inactive.email, nil, "inactive"},
            {nil, nil, creator.email}
          ] do
        sandbox_fixture()
        |> Ecto.Changeset.change(
          amp_creator_user_id: "user_amp",
          amp_creator_email: email,
          amp_creator_username: username,
          amp_creator_name: label
        )
        |> Repo.update!()
      end

    assert Enum.map(Sandboxes.preload_creators(sandboxes), & &1.creator_actor) == [
             %{name: creator.account.name, source: :matched},
             %{name: "unverified", source: :reported},
             %{name: "disabled", source: :reported},
             %{name: "inactive", source: :reported},
             %{name: creator.email, source: :reported}
           ]
  end

  test "Anthropic creators come from the session's authenticated creator in the same account and environment" do
    account = account_fixture()
    creator = user_fixture()
    environment = agent_environment_fixture(account: account)
    session = agent_session_fixture(account: account, agent_environment: environment, created_by_user_id: creator.id)

    sandbox =
      sandbox_fixture(
        account: account,
        agent_environment_id: environment.id,
        anthropic_session_id: session.anthropic_session_id
      )

    external =
      sandbox_fixture(account: account, agent_environment_id: environment.id, anthropic_session_id: "session_external")

    other_environment = agent_environment_fixture(account: account)

    wrong_environment =
      sandbox_fixture(
        account: account,
        agent_environment_id: other_environment.id,
        anthropic_session_id: session.anthropic_session_id
      )

    assert Enum.map(
             Sandboxes.preload_creators([sandbox, external, wrong_environment]),
             & &1.creator_actor
           ) == [
             %{name: creator.account.name, source: :matched},
             %{name: nil, source: :unknown},
             %{name: nil, source: :unknown}
           ]

    other_account = account_fixture()
    sandbox |> Ecto.Changeset.change(account_id: other_account.id) |> Repo.update!()
    assert [%{creator_actor: %{name: nil, source: :unknown}}] = Sandboxes.preload_creators([Repo.reload!(sandbox)])
    sandbox |> Repo.reload!() |> Ecto.Changeset.change(account_id: account.id) |> Repo.update!()

    creator |> Ecto.Changeset.change(disabled_at: DateTime.utc_now(:second)) |> Repo.update!()
    assert [%{creator_actor: %{name: nil, source: :unknown}}] = Sandboxes.preload_creators([sandbox])
  end

  describe "agent environments" do
    test "create_agent_environment/2 stores the key encrypted and lists it back without it" do
      account = account_fixture()

      assert {:ok, %AgentEnvironment{} = agent_environment} =
               Sandboxes.create_agent_environment(account, %{
                 anthropic_environment_id: "env_123",
                 environment_key: "sk-ant-secret",
                 name: "prod",
                 vcpus: 4,
                 memory_mb: 8192
               })

      assert agent_environment.environment_key == "sk-ant-secret"
      assert agent_environment.vcpus == 4
      assert agent_environment.template == "default"

      %{rows: [[stored_key]]} =
        Repo.query!("SELECT environment_key FROM sandbox_agent_environments WHERE id = $1", [agent_environment.id])

      refute stored_key == "sk-ant-secret"
      refute inspect(agent_environment) =~ "sk-ant-secret"

      assert [%AgentEnvironment{id: id}] = Sandboxes.list_agent_environments(account)
      assert id == agent_environment.id
      assert {:ok, %AgentEnvironment{}} = Sandboxes.get_agent_environment(account, agent_environment.id)
      assert {:error, :not_found} = Sandboxes.get_agent_environment(account_fixture(), agent_environment.id)
    end

    test "create_agent_environment/2 rejects a duplicate anthropic environment id" do
      agent_environment = agent_environment_fixture(anthropic_environment_id: "env_dup")

      assert {:error, changeset} =
               Sandboxes.create_agent_environment(account_fixture(), %{
                 anthropic_environment_id: agent_environment.anthropic_environment_id,
                 environment_key: "key"
               })

      assert %{anthropic_environment_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "delete_agent_environment/1 deletes the environment's sandboxes on their nodes first" do
      account = account_fixture()
      agent_environment = agent_environment_fixture(account: account)

      sandbox =
        sandbox_fixture(
          account: account,
          agent_environment_id: agent_environment.id,
          anthropic_session_id: "session_1",
          node_name: "node-a"
        )

      sandbox_id = sandbox.id

      expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: ^sandbox_id}, _opts -> {:ok, %{}} end)

      assert {:ok, _deleted} = Sandboxes.delete_agent_environment(agent_environment)
      assert Repo.get(AgentEnvironment, agent_environment.id) == nil
      assert Repo.get(Sandbox, sandbox_id) == nil
    end
  end

  describe "create_sandbox/2" do
    test "inserts the row, boots the VM on a node with the template and records the placement" do
      account = account_fixture()

      expect(Capacity, :place, fn %{node_name: nil, template: "default"} -> {:ok, "node-a"} end)

      expect(Nodes, :call, fn "node-a", "create", args, opts ->
        assert opts[:timeout] == 120_000
        assert %Sandbox{state: :creating} = Repo.get(Sandbox, args.sandbox_id)
        assert args.hostname == "sbx-" <> String.slice(args.sandbox_id, 0, 8)
        assert args.template == "default"
        # Every Linux sandbox bursts to 16 vCPUs; its shape picks the memory.
        assert args.vcpus == 16
        assert args.memory_mb == 4096
        assert args.workspace_gb == 10
        {:ok, %{"boot_ms" => 180, "template_tag" => "sha-1"}}
      end)

      assert {:ok, %Sandbox{} = sandbox} = Sandboxes.create_sandbox(account, %{})
      assert sandbox.state == :running
      assert sandbox.node_name == "node-a"
      assert sandbox.template_tag == "sha-1"
      assert sandbox.hostname == "sbx-" <> String.slice(sandbox.id, 0, 8)
      assert sandbox.last_active_at
      assert [%Sandbox{id: id}] = Sandboxes.list_sandboxes(account)
      assert id == sandbox.id
      assert events(sandbox) == ["created", "started"]

      assert [%{boot_source: "template"}] =
               ClickHouseRepo.all(
                 from(e in SandboxEvent,
                   where: e.sandbox_id == ^sandbox.id and e.event == "started",
                   select: %{boot_source: e.boot_source}
                 )
               )
    end

    test "records a claimed warm VM as the boot source" do
      account = account_fixture()
      expect(Capacity, :place, fn _sandbox -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{"boot_ms" => 900, "warm" => true}} end)

      assert {:ok, sandbox} = Sandboxes.create_sandbox(account, %{})

      assert [%{boot_source: "warm"}] =
               ClickHouseRepo.all(
                 from(e in SandboxEvent,
                   where: e.sandbox_id == ^sandbox.id and e.event == "started",
                   select: %{boot_source: e.boot_source}
                 )
               )
    end

    test "applies the requested shape" do
      account = account_fixture()

      expect(Capacity, :place, fn %{template: "xcode"} -> {:ok, "node-a"} end)

      expect(Nodes, :call, fn "node-a",
                              "create",
                              %{template: "xcode", vcpus: 16, memory_mb: 16_384, workspace_gb: 40},
                              _ ->
        {:ok, %{}}
      end)

      assert {:ok, %Sandbox{vcpus: 16, memory_mb: 16_384, workspace_gb: 40, template: "xcode"}} =
               Sandboxes.create_sandbox(account, %{template: "xcode", vcpus: 8, memory_mb: 16_384, workspace_gb: 40})
    end

    test "marks the sandbox as errored when no node can host it" do
      account = account_fixture()
      expect(Capacity, :place, fn _ -> {:error, :no_node} end)

      assert {:error, :no_node} = Sandboxes.create_sandbox(account, %{})

      assert [%Sandbox{state: :error, node_name: nil, error_message: message} = sandbox] =
               Sandboxes.list_sandboxes(account)

      assert message =~ "no node"
      assert events(sandbox) == ["created", "failed"]
    end

    test "a create refused for room records no events and, with capacity_wait_ms, waits for room on the same row" do
      account = account_fixture()
      expect(Capacity, :place, 3, fn _ -> {:error, :no_capacity} end)

      assert {:error, :no_capacity} = Sandboxes.create_sandbox(account, %{}, capacity_wait_ms: 25)

      assert [%Sandbox{state: :error, node_name: nil} = refused] = Sandboxes.list_sandboxes(account)
      assert events(refused) == []

      expect(Capacity, :place, 2, fn _ -> {:error, :no_capacity} end)
      expect(Capacity, :place, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

      assert {:ok, %Sandbox{state: :running} = sandbox} = Sandboxes.create_sandbox(account, %{}, capacity_wait_ms: 5_000)
      assert events(sandbox) == ["created", "started"]
    end

    test "a create without capacity_wait_ms answers a refusal at once" do
      account = account_fixture()
      expect(Capacity, :place, fn _ -> {:error, :no_capacity} end)

      assert {:error, :no_capacity} = Sandboxes.create_sandbox(account, %{})
    end

    test "marks the sandbox as errored when the node rejects the create" do
      account = account_fixture()
      expect(Capacity, :place, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:error, "jailer exited with status 1"} end)

      assert {:error, "jailer exited with status 1"} = Sandboxes.create_sandbox(account, %{})
      assert [%Sandbox{state: :error, error_message: "jailer exited with status 1"}] = Sandboxes.list_sandboxes(account)
    end

    test "rejects an invalid shape without touching a node" do
      reject(&Capacity.place/1)
      assert {:error, %Ecto.Changeset{}} = Sandboxes.create_sandbox(account_fixture(), %{vcpus: 0})
    end
  end

  describe "pause/1 and resume/1" do
    test "pause/1 snapshots a running sandbox after syncing its disks" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "amp:orb", residency_epoch: 3)
      sandbox_id = sandbox.id

      expect(Nodes, :call, fn "node-a", "pause", %{sandbox_id: ^sandbox_id, sync_disks: true}, _opts ->
        {:ok, %{"snapshot_ms" => 300, "mem_bytes" => 1024}}
      end)

      assert {:ok, %Sandbox{state: :paused, paused_at: %DateTime{}, residency_work_id: nil, residency_epoch: 4}} =
               Sandboxes.pause(sandbox)

      assert %Sandbox{state: :paused, residency_work_id: nil, residency_epoch: 4} = Repo.reload!(sandbox)
      assert events(sandbox) == ["paused"]
    end

    test "pause/1 bills the time since the last report from the CPU and memory the node read as it paused" do
      # 2 GiB of memory: a guarantee of half a vCPU, 10 s of CPU over 20 s.
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", memory_mb: 2048)
      old_daemon = sandbox_fixture(state: :running, node_name: "node-a")

      Repo.update_all(from(s in Sandbox, where: s.id in ^[sandbox.id, old_daemon.id]),
        set: [metered_cpu_ms: 10_000, metered_at: DateTime.add(DateTime.utc_now(), -20, :second)]
      )

      stub(Nodes, :call, fn "node-a", "pause", %{sandbox_id: id}, _opts ->
        if id == sandbox.id,
          # 2612 MiB at the pause: 500 MiB past the request and the VMM's 64 MiB.
          do:
            {:ok,
             %{
               "snapshot_ms" => 300,
               "mem_bytes" => 1024,
               "cpu_ms" => 30_000,
               "memory_anon_bytes" => 2500 * 1024 * 1024,
               "memory_file_bytes" => 112 * 1024 * 1024
             }},
          else: {:ok, %{"snapshot_ms" => 300, "mem_bytes" => 1024}}
      end)

      assert {:ok, %Sandbox{state: :paused, metered_at: nil}} = Sandboxes.pause(sandbox)
      assert {:ok, %Sandbox{state: :paused}} = Sandboxes.pause(old_daemon)

      assert [%{sandbox_id: sandbox_id, used: 20_000, billed: 20_000, duration_ms: duration_ms, excess: excess}] =
               ClickHouseRepo.all(
                 from(u in UsageEvent,
                   where: u.sandbox_id in ^[sandbox.id, old_daemon.id],
                   select: %{
                     sandbox_id: u.sandbox_id,
                     used: u.used_cpu_ms,
                     billed: u.billed_cpu_ms,
                     duration_ms: u.duration_ms,
                     excess: u.excess_memory_mib_ms
                   }
                 )
               )

      assert sandbox_id == sandbox.id
      assert duration_ms in 20_000..20_500
      assert excess == 500 * duration_ms
    end

    test "pause/1 leaves the sandbox running when the node refuses" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:error, "worker running"} end)

      assert {:error, "worker running"} = Sandboxes.pause(sandbox)
      assert %Sandbox{state: :running} = Repo.reload!(sandbox)
    end

    test "pause/1 refuses a sandbox that is not running" do
      assert {:error, {:invalid_state, :paused}} = Sandboxes.pause(sandbox_fixture(state: :paused))
      assert {:error, {:invalid_state, :error}} = Sandboxes.pause(sandbox_fixture(state: :error))
    end

    test "resume/1 restores a paused sandbox" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a", paused_at: DateTime.utc_now())
      sandbox_id = sandbox.id

      expect(Nodes, :call, fn "node-a", "resume", %{sandbox_id: ^sandbox_id}, opts ->
        assert opts[:timeout] == 120_000
        {:ok, %{"restore_ms" => 90}}
      end)

      assert {:ok, %Sandbox{state: :running, paused_at: nil, last_active_at: %DateTime{}}} = Sandboxes.resume(sandbox)
    end

    test "resume/1 keeps the sandbox paused when its node is away" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:error, :not_connected} end)

      assert {:error, :not_connected} = Sandboxes.resume(sandbox)
      assert %Sandbox{state: :paused} = Repo.reload!(sandbox)
    end

    test "resume/1 marks the sandbox as errored when the node fails the restore" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:error, "snapshot load failed"} end)

      assert {:error, "snapshot load failed"} = Sandboxes.resume(sandbox)
      assert %Sandbox{state: :error, error_message: "snapshot load failed"} = Repo.reload!(sandbox)
    end

    test "resume/1 holds the memory reservation through the restore and drops it on a transient failure" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a")

      expect(Nodes, :call, fn "node-a", "resume", %{sandbox_id: sandbox_id}, _opts ->
        assert %Sandbox{state: :resuming} = Repo.get(Sandbox, sandbox_id)
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Sandboxes.resume(sandbox)
      assert %Sandbox{state: :paused} = Repo.reload!(sandbox)
    end

    test "resume/1 refuses without touching the node when the node has no room" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a")
      expect(Capacity, :admit, fn %Sandbox{state: :paused} -> {:error, :no_capacity} end)
      reject(&Nodes.call/4)

      assert {:error, :no_capacity} = Sandboxes.resume(sandbox)
      assert %Sandbox{state: :paused} = Repo.reload!(sandbox)
    end

    test "ensure_running/1 resumes only when paused" do
      running = sandbox_fixture(state: :running)
      assert {:ok, ^running} = Sandboxes.ensure_running(running)

      paused = sandbox_fixture(state: :paused, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)
      assert {:ok, %Sandbox{state: :running}} = Sandboxes.ensure_running(paused)

      assert {:error, {:invalid_state, :error}} = Sandboxes.ensure_running(sandbox_fixture(state: :error))
    end
  end

  describe "delete/1" do
    test "tears the VM down on its node and removes the row" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      sandbox_id = sandbox.id

      expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: ^sandbox_id}, _opts ->
        assert %Sandbox{state: :deleted} = Repo.get(Sandbox, sandbox_id)
        {:ok, %{}}
      end)

      assert {:ok, %Sandbox{}} = Sandboxes.delete(sandbox)
      assert Repo.get(Sandbox, sandbox_id) == nil
      assert events(sandbox) == ["deleted"]
    end

    test "removes the row when the node is not connected" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-gone")
      expect(Nodes, :call, fn "node-gone", "delete", _args, _opts -> {:error, :not_connected} end)

      assert {:ok, %Sandbox{}} = Sandboxes.delete(sandbox)
      assert Repo.get(Sandbox, sandbox.id) == nil
    end

    test "removes a row that never reached a node" do
      sandbox = sandbox_fixture(state: :error, node_name: nil)
      reject(&Nodes.call/4)

      assert {:ok, %Sandbox{}} = Sandboxes.delete(sandbox)
      assert Repo.get(Sandbox, sandbox.id) == nil
    end

    test "keeps the row as errored when the node fails the delete" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:error, "netns busy"} end)

      assert {:error, "netns busy"} = Sandboxes.delete(sandbox)
      assert %Sandbox{state: :error, error_message: "netns busy"} = Repo.reload!(sandbox)
    end
  end

  describe "exec/3" do
    test "streams the command output back and returns the exit code" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      sandbox_id = sandbox.id

      expect(Nodes, :call, fn "node-a", "exec", args, opts ->
        assert %{sandbox_id: ^sandbox_id, cmd: ["/bin/bash", "-lc", "ls"], cwd: "/workspace", timeout_ms: 5_000} = args
        assert opts[:timeout] == 15_000
        opts[:on_stream].({:stdout, "a\n"})
        opts[:on_stream].({:stderr, "warn\n"})
        opts[:on_stream].({:stdout, "b\n"})
        {:ok, %{"exit_code" => 3}}
      end)

      assert {:ok, %{exit_code: 3, stdout: "a\nb\n", stderr: "warn\n"}} =
               Sandboxes.exec(sandbox, ["/bin/bash", "-lc", "ls"], timeout_ms: 5_000)
    end

    test "resumes a paused sandbox before running the command" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a")

      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %{exit_code: 0, stdout: "", stderr: ""}} = Sandboxes.exec(sandbox, ["/bin/true"])
      assert %Sandbox{state: :running} = Repo.reload!(sandbox)
    end

    test "waits out a pause the command raced with, then resumes the sandbox and runs it" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")

      # The idle pause reached the node first; by the time the exec retries,
      # the row says paused.
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts ->
        sandbox |> Ecto.Changeset.change(state: :paused) |> Repo.update!()
        {:error, "sandbox is being paused: #{sandbox.id}"}
      end)

      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)

      assert {:ok, %{exit_code: 0}} = Sandboxes.exec(sandbox, ["/bin/true"])
      assert %Sandbox{state: :running} = Repo.reload!(sandbox)
    end

    test "returns the node error" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:error, :timeout} end)

      assert {:error, :timeout} = Sandboxes.exec(sandbox, ["/bin/sleep", "100"])
    end
  end

  describe "residencies and node events" do
    test "worker_exited clears the residency, bumps the epoch and schedules the pause" do
      agent_environment = agent_environment_fixture(pause_grace_seconds: 45)

      sandbox =
        sandbox_fixture(
          state: :running,
          node_name: "node-a",
          agent_environment_id: agent_environment.id,
          anthropic_session_id: "session_1",
          residency_work_id: "work_1",
          residency_epoch: 1
        )

      assert :ok =
               Sandboxes.handle_node_event("node-a", %{
                 "event" => "worker_exited",
                 "sandbox_id" => sandbox.id,
                 "exit_code" => 0,
                 "duration_ms" => 10
               })

      assert %Sandbox{residency_work_id: nil, residency_epoch: 2, last_active_at: %DateTime{}} = Repo.reload!(sandbox)

      assert [job] = all_enqueued(worker: PauseSandboxWorker)
      assert job.args == %{"sandbox_id" => sandbox.id, "residency_epoch" => 2}
      assert DateTime.diff(job.scheduled_at, DateTime.utc_now()) in 40..46
    end

    test "a second worker_exited replaces the pending pause with the newer epoch" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 0)

      assert :ok = Sandboxes.handle_node_event("node-a", %{"event" => "worker_exited", "sandbox_id" => sandbox.id})
      assert {:ok, _} = Sandboxes.begin_residency(Repo.reload!(sandbox), "work_2")
      assert :ok = Sandboxes.handle_node_event("node-a", %{"event" => "worker_exited", "sandbox_id" => sandbox.id})

      assert [job] = all_enqueued(worker: PauseSandboxWorker)
      assert job.args == %{"sandbox_id" => sandbox.id, "residency_epoch" => 3}
    end

    test "worker_exited for an unknown sandbox is ignored" do
      assert :ok =
               Sandboxes.handle_node_event("node-a", %{"event" => "worker_exited", "sandbox_id" => Ecto.UUID.generate()})

      assert [] = all_enqueued(worker: PauseSandboxWorker)
    end

    test "sandbox_died marks the sandbox as errored and ends its residency" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "work_1", residency_epoch: 4)

      assert :ok =
               Sandboxes.handle_node_event("node-a", %{
                 "event" => "sandbox_died",
                 "sandbox_id" => sandbox.id,
                 "reason" => "firecracker exited"
               })

      assert %Sandbox{state: :error, error_message: "firecracker exited", residency_work_id: nil, residency_epoch: 5} =
               Repo.reload!(sandbox)

      assert events(sandbox) == ["failed"]
    end
  end

  describe "reconcile_node_report/2" do
    test "a node pause ends residency and records its observation time, including already paused legacy rows" do
      for state <- [:running, :paused] do
        sandbox =
          [
            state: state,
            node_name: "node-a",
            amp_orb_id: "orb-#{state}",
            residency_work_id: "amp:orb",
            residency_epoch: 3
          ]
          |> sandbox_fixture()
          |> backdate(60)

        report = %{"sandboxes" => [%{"id" => sandbox.id, "state" => "paused"}]}
        before_report = DateTime.utc_now(:second)
        assert :ok = Sandboxes.reconcile_node_report("node-a", report)

        assert %Sandbox{state: :paused, paused_at: %DateTime{} = at, residency_work_id: nil, residency_epoch: 4} =
                 Repo.reload!(sandbox)

        refute DateTime.before?(at, before_report)
        assert Archives.archivable?(Repo.reload!(sandbox))

        assert :ok = Sandboxes.reconcile_node_report("node-a", report)
        assert %Sandbox{paused_at: ^at, residency_epoch: 4} = Repo.reload!(sandbox)
      end
    end

    test "a delayed paused report cannot end a freshly started turn" do
      sandbox =
        sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "amp:new", residency_epoch: 7)

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => sandbox.id, "state" => "paused"}]})

      assert %Sandbox{state: :running, paused_at: nil, residency_work_id: "amp:new", residency_epoch: 7} =
               Repo.reload!(sandbox)
    end

    test "a paused copy on a former node cannot release the current node's residency" do
      sandbox =
        [state: :running, node_name: "node-b", residency_work_id: "amp:new", residency_epoch: 7]
        |> sandbox_fixture()
        |> backdate(60)

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => sandbox.id, "state" => "paused"}]})

      assert %Sandbox{
               state: :running,
               node_name: "node-b",
               paused_at: nil,
               residency_work_id: "amp:new",
               residency_epoch: 7
             } =
               Repo.reload!(sandbox)

      assert events(sandbox) == []
    end

    test "repairs a missing pause time without residency, but preserves a known pause time" do
      known_time = DateTime.add(DateTime.utc_now(:second), -3600, :second)

      for paused_at <- [nil, known_time] do
        sandbox = sandbox_fixture(state: :paused, node_name: "node-a", paused_at: paused_at)
        report = %{"sandboxes" => [%{"id" => sandbox.id, "state" => "paused"}]}

        assert :ok = Sandboxes.reconcile_node_report("node-a", report)
        assert %Sandbox{paused_at: %DateTime{} = recorded, residency_epoch: 0} = Repo.reload!(sandbox)
        if paused_at, do: assert(recorded == known_time)
        assert Archives.archivable?(Repo.reload!(sandbox))
      end
    end

    test "a resume between reading and applying a paused report wins" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a", residency_work_id: "amp:old", residency_epoch: 3)

      expect(Repo, :update_all, fn query, updates ->
        Mimic.call_original(Repo, :update_all, [
          from(s in Sandbox, where: s.id == ^sandbox.id),
          [set: [state: :running, residency_work_id: "amp:new", paused_at: nil], inc: [residency_epoch: 1]]
        ])

        Mimic.call_original(Repo, :update_all, [query, updates])
      end)

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => sandbox.id, "state" => "paused"}]})

      assert %Sandbox{state: :running, residency_work_id: "amp:new", residency_epoch: 4, paused_at: nil} =
               Repo.reload!(sandbox)

      assert events(sandbox) == []
    end

    test "records guest activity only when the guest used CPU since the last activity" do
      quiet_since = DateTime.truncate(DateTime.add(DateTime.utc_now(), -100, :second), :second)
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", guest_cpu_ms: 1000, last_active_at: quiet_since)
      report = fn cpu_ms -> %{"sandboxes" => [%{"id" => sandbox.id, "state" => "running", "cpu_ms" => cpu_ms}]} end

      # 100 seconds at 2% of one vCPU is 2 s of CPU.
      assert :ok = Sandboxes.reconcile_node_report("node-a", report.(2500))
      assert %Sandbox{guest_cpu_ms: 1000, last_active_at: ^quiet_since} = Repo.reload!(sandbox)

      assert :ok = Sandboxes.reconcile_node_report("node-a", report.(4000))
      assert %Sandbox{guest_cpu_ms: 4000, last_active_at: active_at} = Repo.reload!(sandbox)
      assert DateTime.after?(active_at, quiet_since)

      # A new VM process starts its count again.
      assert :ok = Sandboxes.reconcile_node_report("node-a", report.(50))
      assert %Sandbox{guest_cpu_ms: 50} = Repo.reload!(sandbox)
    end

    test "bills a running Linux sandbox the larger of its memory's CPU floor and the CPU it used at each report" do
      # 2 GiB of memory: a floor of half a vCPU, above its quarter-core guarantee.
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", memory_mb: 2048)
      darwin = sandbox_fixture(state: :running, node_name: "node-a", platform: :darwin, vcpus: 8, memory_mb: 8192)
      execution = sandbox_fixture(state: :running, node_name: "node-a", purpose: :remote_execution)

      report = fn cpu_ms, seconds_since_last ->
        Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id and not is_nil(s.metered_at)),
          set: [metered_at: DateTime.add(DateTime.utc_now(), -seconds_since_last, :second)]
        )

        reported = for s <- [sandbox, darwin, execution], do: %{"id" => s.id, "state" => "running", "cpu_ms" => cpu_ms}
        assert :ok = Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => reported})
      end

      # The first report of a run bills the CPU its VM used since it started.
      report.(5_000, 0)
      # Idle for 30 s: half a vCPU over 30 s is 15 s.
      report.(6_000, 30)
      # Bursting: 29 s of CPU in 30 s.
      report.(35_000, 30)
      # A gap, such as a server restart, bills the floor for one minute.
      report.(36_000, 600)
      # A new VM process counts from zero.
      report.(2_000, 30)

      rows =
        ClickHouseRepo.all(
          from(u in UsageEvent,
            where: u.sandbox_id in ^[sandbox.id, darwin.id, execution.id],
            order_by: u.inserted_at,
            select: %{sandbox_id: u.sandbox_id, used: u.used_cpu_ms, billed: u.billed_cpu_ms}
          )
        )

      assert Enum.all?(rows, &(&1.sandbox_id == sandbox.id))
      assert [5_000, 1_000, 29_000, 1_000, 2_000] = Enum.map(rows, & &1.used)
      assert [5_000, idle, 29_000, gap, new_process] = Enum.map(rows, & &1.billed)
      assert idle in 15_000..15_100 and new_process in 15_000..15_100 and gap in 30_000..30_100

      # A pause ends the run, so the next one starts its metering over. The
      # report adopts a pause once the last running report has settled, and
      # bills the time since the last report up to the CPU reading the node
      # took at the pause: 7 s used in 10 s, above the floor's 5 s.
      Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id),
        set: [
          updated_at: DateTime.add(DateTime.utc_now(:second), -60, :second),
          metered_at: DateTime.add(DateTime.utc_now(), -10, :second)
        ]
      )

      paused = %{"sandboxes" => [%{"id" => sandbox.id, "state" => "paused", "cpu_ms" => 9_000}]}
      assert :ok = Sandboxes.reconcile_node_report("node-a", paused)
      assert %Sandbox{state: :paused, metered_cpu_ms: nil, metered_at: nil} = Repo.reload!(sandbox)

      # The paused sandbox keeps reporting that reading; it is billed once.
      assert :ok = Sandboxes.reconcile_node_report("node-a", paused)

      usage =
        ClickHouseRepo.all(
          from(u in UsageEvent,
            where: u.sandbox_id == ^sandbox.id,
            order_by: u.inserted_at,
            select: %{used: u.used_cpu_ms, billed: u.billed_cpu_ms}
          )
        )

      assert [%{used: 7_000, billed: 7_000}] = Enum.drop(usage, 5)
    end

    test "bills a running Linux sandbox the memory its VM held past its request" do
      # 2 GiB of guest memory and the VMM's 64 MiB: 2112 MiB before any excess.
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", memory_mb: 2048)
      mib = 1024 * 1024

      report = fn reading, seconds_since_last ->
        Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id and not is_nil(s.metered_at)),
          set: [metered_at: DateTime.add(DateTime.utc_now(), -seconds_since_last, :second)]
        )

        reported = Map.merge(%{"id" => sandbox.id, "state" => "running", "cpu_ms" => 1_000}, reading)
        assert :ok = Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [reported]})
      end

      # The first report of a run covers no interval.
      report.(%{"memory_anon_bytes" => 3000 * mib, "memory_file_bytes" => 112 * mib}, 0)
      # 3112 MiB held for 30 s: 1000 MiB past the request, anonymous and file pages alike.
      report.(%{"memory_anon_bytes" => 3000 * mib, "memory_file_bytes" => 112 * mib}, 30)
      # Under its request it is billed the request alone.
      report.(%{"memory_anon_bytes" => 1500 * mib, "memory_file_bytes" => 100 * mib}, 30)
      # A daemon that does not read the VM's memory leaves no excess.
      report.(%{}, 30)

      rows =
        ClickHouseRepo.all(
          from(u in UsageEvent,
            where: u.sandbox_id == ^sandbox.id,
            order_by: u.inserted_at,
            select: %{used: u.used_memory_bytes, excess: u.excess_memory_mib_ms}
          )
        )

      assert [3112, 3112, 1600, 0] = Enum.map(rows, &div(&1.used, mib))
      assert [0, excess, 0, 0] = Enum.map(rows, & &1.excess)
      assert excess in (1000 * 30_000)..(1000 * 30_100)
    end

    test "queues a pause for a running Orb whose guest has been quiet for ten minutes" do
      quiet_since = DateTime.truncate(DateTime.add(DateTime.utc_now(), -601, :second), :second)

      orb =
        sandbox_fixture(
          state: :running,
          node_name: "node-a",
          amp_orb_id: "orb-quiet",
          residency_work_id: "amp:orb-quiet",
          guest_cpu_ms: 1000,
          last_active_at: quiet_since
        )

      recent =
        sandbox_fixture(
          state: :running,
          node_name: "node-a",
          amp_orb_id: "orb-recent",
          guest_cpu_ms: 1000,
          last_active_at: DateTime.add(DateTime.utc_now(), -300, :second)
        )

      api = sandbox_fixture(state: :running, node_name: "node-a", guest_cpu_ms: 1000, last_active_at: quiet_since)

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{
                 "sandboxes" => for(s <- [orb, recent, api], do: %{"id" => s.id, "state" => "running", "cpu_ms" => 1100})
               })

      assert [%Oban.Job{args: args}] = all_enqueued(worker: PauseIdleOrbWorker)
      assert args == %{"sandbox_id" => orb.id, "last_active_at" => DateTime.to_iso8601(quiet_since)}
    end

    test "never treats a guest as quiet before its node reports CPU time" do
      orb =
        sandbox_fixture(
          state: :running,
          node_name: "node-a",
          amp_orb_id: "orb-old-daemon",
          last_active_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        )

      assert :ok = Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => orb.id, "state" => "running"}]})
      assert [] = all_enqueued(worker: PauseIdleOrbWorker)
    end

    test "does not downgrade a resuming sandbox the node still lists as paused" do
      sandbox = sandbox_fixture(state: :resuming, node_name: "node-a", template_tag: "sha-1")

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{
                 "sandboxes" => [%{"id" => sandbox.id, "state" => "paused", "template_tag" => "sha-2"}]
               })

      assert %Sandbox{state: :resuming, template_tag: "sha-2"} = Repo.reload!(sandbox)
    end

    test "adopts reported sandboxes, errors the missing ones and deletes orphans" do
      reported = sandbox_fixture(state: :error, node_name: nil, error_message: "missing on node")
      moved = sandbox_fixture(state: :running, node_name: "node-b")

      missing =
        [state: :paused, node_name: "node-a", residency_work_id: "work_9", residency_epoch: 1]
        |> sandbox_fixture()
        |> backdate(60)

      untouched = sandbox_fixture(state: :creating, node_name: nil)
      # Created a moment ago: the report may predate it.
      just_created = sandbox_fixture(state: :running, node_name: "node-a")
      orphan_id = Ecto.UUID.generate()

      expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: ^orphan_id}, _opts -> {:ok, %{}} end)

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{
                 "sandboxes" => [
                   %{"id" => reported.id, "state" => "paused", "template_tag" => "sha-2"},
                   %{"id" => moved.id, "state" => "running"},
                   %{"id" => orphan_id, "state" => "running"},
                   %{"id" => "not-a-uuid", "state" => "running"}
                 ]
               })

      assert %Sandbox{state: :paused, node_name: "node-a", template_tag: "sha-2", error_message: nil} =
               Repo.reload!(reported)

      assert %Sandbox{state: :running, node_name: "node-a"} = Repo.reload!(moved)

      assert %Sandbox{state: :error, node_name: "node-a", error_message: "missing on node", residency_work_id: nil} =
               Repo.reload!(missing)

      assert %Sandbox{state: :creating, node_name: nil} = Repo.reload!(untouched)
      assert %Sandbox{state: :running, error_message: nil} = Repo.reload!(just_created)
    end

    test "leaves a sandbox being deleted alone" do
      deleting = sandbox_fixture(state: :deleted, node_name: "node-a")
      reject(&Nodes.call/4)

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => deleting.id, "state" => "running"}]})

      assert %Sandbox{state: :deleted} = Repo.reload!(deleting)
    end

    test "leaves execution VMs to their scheduler" do
      reported = sandbox_fixture(state: :creating, node_name: "node-a")
      unreported = sandbox_fixture(state: :running, node_name: "node-a")

      for sandbox <- [reported, unreported] do
        sandbox |> Ecto.Changeset.change(purpose: :remote_execution) |> Repo.update!()
      end

      reject(&Nodes.call/4)

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => reported.id, "state" => "error"}]})

      assert %Sandbox{state: :creating, error_message: nil} = Repo.reload!(reported)
      assert %Sandbox{state: :running, error_message: nil} = Repo.reload!(unreported)
    end
  end

  describe "listing an account's sandboxes" do
    test "leaves out execution VMs" do
      account = account_fixture()
      agent = sandbox_fixture(account: account, vcpus: 2)

      [account: account, vcpus: 8]
      |> sandbox_fixture()
      |> Ecto.Changeset.change(purpose: :remote_execution)
      |> Repo.update!()

      assert [%Sandbox{id: id}] = Sandboxes.list_sandboxes(account)
      assert id == agent.id
      assert Sandboxes.count_sandboxes(account) == 1
      assert Sandboxes.sandbox_vcpus(account) == [2]
      assert %{running: 1} = Sandboxes.count_sandboxes_by_state(account)
    end
  end

  defp backdate(sandbox, seconds) do
    at = DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(s in Sandbox, where: s.id == ^sandbox.id), set: [updated_at: at])
    Repo.reload!(sandbox)
  end

  describe "reconcile_node_report/2 with in-flight and failed sandboxes" do
    test "settles a resuming sandbox the node already runs" do
      sandbox = sandbox_fixture(state: :resuming, node_name: "node-a")
      reject(&Nodes.call/4)

      Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => sandbox.id, "state" => "running"}]})

      assert %Sandbox{state: :running} = Repo.reload!(sandbox)
    end

    test "moves a resuming sandbox whose caller died back to paused once it has been stuck long enough" do
      sandbox = [state: :resuming, node_name: "node-a"] |> sandbox_fixture() |> backdate(600)

      Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => sandbox.id, "state" => "paused"}]})

      assert %Sandbox{state: :paused} = Repo.reload!(sandbox)
    end

    test "errors a sandbox the node reports in error with the node's reason" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "work_1", residency_epoch: 2)

      Sandboxes.reconcile_node_report("node-a", %{
        "sandboxes" => [%{"id" => sandbox.id, "state" => "error", "error" => "sandbox is missing rootfs.ext4"}]
      })

      assert %Sandbox{
               state: :error,
               error_message: "sandbox is missing rootfs.ext4",
               residency_work_id: nil,
               residency_epoch: 3
             } =
               Repo.reload!(sandbox)
    end

    test "puts a restore whose node lost the lazy disks it was loading back to archived, even once errored" do
      restore = fn opts ->
        [
          node_name: "node-a",
          archived_at: DateTime.utc_now(),
          archive_key: "sandbox-archives/x.sbxa",
          archive_memory: %{"lazy_disks" => true, "loading_since" => DateTime.to_iso8601(DateTime.utc_now())}
        ]
        |> Keyword.merge(opts)
        |> sandbox_fixture()
      end

      running = restore.(state: :running, amp_orb_id: "amp-1", residency_work_id: "amp:amp-1", residency_epoch: 2)
      errored = restore.(state: :error, error_message: "daemon restarted while loading")
      loaded = restore.(state: :running, archive_memory: %{"lazy_disks" => true, "loaded" => true})
      reject(&Nodes.call/4)

      Sandboxes.reconcile_node_report("node-a", %{
        "sandboxes" =>
          for(
            sandbox <- [running, errored, loaded],
            do: %{"id" => sandbox.id, "state" => "error", "error" => "restarted"}
          )
      })

      for sandbox <- [running, errored] do
        # The next restore may boot cold, which would never clear `loading_since`.
        assert %Sandbox{
                 state: :archived,
                 node_name: nil,
                 residency_work_id: nil,
                 archive_key: "sandbox-archives/x.sbxa",
                 archive_memory: %{"lazy_disks" => true} = memory
               } = Repo.reload!(sandbox)

        refute Map.has_key?(memory, "loading_since")
      end

      assert %Sandbox{residency_epoch: 3} = Repo.reload!(running)
      # The running restore stopped; the errored one had already.
      assert events(running) == ["failed"]
      assert events(errored) == []
      assert %Sandbox{state: :error, error_message: "restarted", node_name: "node-a"} = Repo.reload!(loaded)
    end

    test "leaves a restore running on another node alone when its former node reports its stale copy in error" do
      restored =
        sandbox_fixture(
          state: :running,
          node_name: "node-b",
          residency_work_id: "amp:amp-1",
          archived_at: DateTime.utc_now(),
          archive_key: "sandbox-archives/x.sbxa",
          archive_memory: %{"lazy_disks" => true, "loading_since" => DateTime.to_iso8601(DateTime.utc_now())}
        )

      restored_id = restored.id
      expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: ^restored_id}, _opts -> {:ok, %{}} end)

      Sandboxes.reconcile_node_report("node-a", %{
        "sandboxes" => [%{"id" => restored.id, "state" => "error", "error" => "restarted"}]
      })

      assert %Sandbox{state: :running, node_name: "node-b", residency_work_id: "amp:amp-1", error_message: nil} =
               Repo.reload!(restored)
    end

    test "errors a creating sandbox the node never got once it has been stuck, and leaves a fresh one alone" do
      stuck = [state: :creating, node_name: "node-a"] |> sandbox_fixture() |> backdate(600)
      fresh = sandbox_fixture(state: :creating, node_name: "node-a")
      resuming = [state: :resuming, node_name: "node-a"] |> sandbox_fixture() |> backdate(60)

      Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => []})

      assert %Sandbox{state: :error, error_message: "missing on node"} = Repo.reload!(stuck)
      assert %Sandbox{state: :creating} = Repo.reload!(fresh)
      assert %Sandbox{state: :error, error_message: "missing on node"} = Repo.reload!(resuming)
    end
  end

  describe "release_removed_nodes/0" do
    test "releases the Linux sandboxes of a disconnected node whose Kubernetes Node is gone" do
      account = account_fixture()
      on_gone = &sandbox_fixture(Keyword.merge([account: account, node_name: "node-gone"], &1))

      running = on_gone.(state: :running, amp_orb_id: "amp-1", residency_work_id: "amp:amp-1", residency_epoch: 2)
      paused = on_gone.(state: :paused, paused_at: DateTime.utc_now())
      restoring = on_gone.(state: :creating, archived_at: DateTime.utc_now(), archive_key: "sandbox-archives/x.sbxa")

      loading =
        on_gone.(
          state: :running,
          archived_at: DateTime.utc_now(),
          archive_key: "sandbox-archives/y.sbxa",
          archive_memory: %{"lazy_disks" => true}
        )

      macos = on_gone.(state: :paused, platform: :darwin)
      execution = on_gone.(state: :running, purpose: :remote_execution)
      away = sandbox_fixture(account: account, state: :running, node_name: "node-away")
      unknown = sandbox_fixture(account: account, state: :running, node_name: "node-api-down")
      live = sandbox_fixture(account: account, state: :running, node_name: "node-live")

      stub(Nodes, :connected?, fn name -> name == "node-live" end)

      stub(Tuist.Kubernetes.Client, :get_node, fn
        "node-gone", _opts -> {:error, :not_found}
        "node-away", _opts -> {:ok, %{"metadata" => %{"name" => "node-away"}}}
        "node-api-down", _opts -> {:error, :timeout}
      end)

      Sandboxes.release_removed_nodes()

      assert %Sandbox{state: :error, node_name: nil, residency_work_id: nil, residency_epoch: 3} = Repo.reload!(running)
      assert %Sandbox{state: :error, node_name: nil} = Repo.reload!(paused)
      assert %Sandbox{state: :archived, node_name: nil} = Repo.reload!(restoring)
      assert %Sandbox{state: :archived, node_name: nil} = Repo.reload!(loading)
      assert %Sandbox{state: :paused, node_name: "node-gone"} = Repo.reload!(macos)
      assert %Sandbox{state: :running, node_name: "node-gone"} = Repo.reload!(execution)
      assert %Sandbox{state: :running, node_name: "node-away"} = Repo.reload!(away)
      assert %Sandbox{state: :running, node_name: "node-api-down"} = Repo.reload!(unknown)
      assert %Sandbox{state: :running, node_name: "node-live"} = Repo.reload!(live)
    end
  end

  describe "pause_idle/2" do
    test "pauses a running sandbox with no residency and matching epoch" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 4)
      sandbox_id = sandbox.id
      expect(Nodes, :call, fn "node-a", "pause", %{sandbox_id: ^sandbox_id}, _opts -> {:ok, %{}} end)

      assert {:ok, %Sandbox{state: :paused}} = Sandboxes.pause_idle(sandbox.id, residency_epoch: 4)
    end

    test "skips a sandbox with a residency or a newer epoch" do
      resident = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "work_1")
      newer = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 5)
      reject(&Nodes.call/4)

      assert {:ok, :skipped} = Sandboxes.pause_idle(resident.id)
      assert {:ok, :skipped} = Sandboxes.pause_idle(newer.id, residency_epoch: 4)
    end

    test "does not wait for a sandbox another process holds the lock of when asked not to" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      test_pid = self()

      holder =
        spawn(fn ->
          Sandboxes.with_sandbox_lock(sandbox.id, fn ->
            send(test_pid, :locked)

            receive do
              :release -> :ok
            end
          end)
        end)

      assert_receive :locked
      reject(&Nodes.call/4)

      assert {:error, :locked} = Sandboxes.pause_idle(sandbox.id, wait: false)
      send(holder, :release)
    end
  end

  describe "residencies" do
    test "begin_residency/2 refuses a sandbox that is not running" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a")

      assert {:error, :not_running} = Sandboxes.begin_residency(sandbox, "work_1")
      assert %Sandbox{residency_work_id: nil, residency_epoch: 0} = Repo.reload!(sandbox)
    end

    test "begin and end increment the epoch from the row, not from a stale struct" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 0)

      assert {:ok, %Sandbox{residency_epoch: 1}} = Sandboxes.begin_residency(sandbox, "work_1")
      assert {:ok, %Sandbox{residency_epoch: 2, residency_work_id: nil}} = Sandboxes.end_residency(sandbox)
    end
  end

  describe "exec/3 output" do
    test "drops output past the cap as it arrives and replaces invalid UTF-8" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      chunk = :binary.copy("a", 256 * 1024)

      expect(Nodes, :call, fn "node-a", "exec", _args, opts ->
        for _ <- 1..12, do: opts[:on_stream].({:stdout, chunk})
        opts[:on_stream].({:stderr, <<0xFF, 0xFE, "tail">>})
        {:message_queue_len, queued} = Process.info(self(), :message_queue_len)
        assert queued <= 5
        {:ok, %{"exit_code" => 0}}
      end)

      assert {:ok, %{stdout: stdout, stderr: stderr}} = Sandboxes.exec(sandbox, ["yes"])
      assert byte_size(stdout) == 1_048_576
      assert String.valid?(stderr)
      assert stderr =~ "tail"
    end
  end

  describe "limits and shapes" do
    test "running sandboxes are bounded by the account's CPU and memory quota, not by a count" do
      account = account_fixture()
      # 10 × 2 vCPU / 4 GiB stays inside the default 32 vCPU / 64 GiB quota.
      for _ <- 1..10, do: sandbox_fixture(account: account, state: :running, node_name: "node-a")
      paused = sandbox_fixture(account: account, state: :paused, node_name: "node-a")

      expect(Capacity, :place, fn _sandbox -> {:error, :no_capacity} end)
      assert {:error, :no_capacity} = Sandboxes.create_sandbox(account, %{})

      expect(Capacity, :admit, fn _sandbox -> {:error, :no_capacity} end)
      assert {:error, :no_capacity} = Sandboxes.resume(paused)
    end

    test "refuses a shape the nodes do not offer" do
      reject(&Capacity.place/1)

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Sandboxes.create_sandbox(account_fixture(), %{vcpus: 4, memory_mb: 4096})

      assert Keyword.has_key?(errors, :memory_mb)

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Sandboxes.create_sandbox(account_fixture(), %{workspace_gb: 500})

      assert Keyword.has_key?(errors, :workspace_gb)
    end
  end

  describe "idle pauses" do
    test "a create schedules the idle pause and an exec replaces it with a later one" do
      account = account_fixture()
      expect(Capacity, :place, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

      assert {:ok, %Sandbox{id: id, residency_epoch: 0}} = Sandboxes.create_sandbox(account, %{})

      assert [%Oban.Job{args: %{"sandbox_id" => ^id, "residency_epoch" => 0}, scheduled_at: first}] =
               all_enqueued(worker: PauseSandboxWorker)

      Process.sleep(1100)
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)
      assert {:ok, %{exit_code: 0}} = Sandboxes.exec(Repo.get!(Sandbox, id), ["true"])

      assert [%Oban.Job{args: %{"sandbox_id" => ^id}, scheduled_at: second}] = all_enqueued(worker: PauseSandboxWorker)
      assert DateTime.after?(second, first)
    end

    test "a resume through the API schedules the idle pause" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a", residency_epoch: 3)
      sandbox_id = sandbox.id
      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)

      assert {:ok, %Sandbox{state: :running}} = Sandboxes.resume(sandbox)

      assert [%Oban.Job{args: %{"sandbox_id" => ^sandbox_id, "residency_epoch" => 3}}] =
               all_enqueued(worker: PauseSandboxWorker)
    end

    test "a restore's memory_loaded pauses it again when idle, after the node refused while its disks loaded" do
      idle = sandbox_fixture(state: :running, node_name: "node-a", residency_epoch: 5)
      busy = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "work_1")
      elsewhere = sandbox_fixture(state: :running, node_name: "node-b")
      idle_id = idle.id

      for sandbox <- [idle, busy, elsewhere] do
        assert :ok = Sandboxes.handle_node_event("node-a", %{"event" => "memory_loaded", "sandbox_id" => sandbox.id})
      end

      assert [%Oban.Job{args: %{"sandbox_id" => ^idle_id, "residency_epoch" => 5}}] =
               all_enqueued(worker: PauseSandboxWorker)
    end

    test "a residency starting after the resume turns the scheduled idle pause into a no-op" do
      sandbox = sandbox_fixture(state: :paused, node_name: "node-a", residency_epoch: 3)
      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)

      assert {:ok, %Sandbox{residency_epoch: 4}} = Sandboxes.prepare_residency(sandbox, "work_1")
      assert [%Oban.Job{args: args}] = all_enqueued(worker: PauseSandboxWorker)

      reject(&Nodes.call/4)
      assert :ok = perform_job(PauseSandboxWorker, args)
      assert %Sandbox{state: :running} = Repo.reload!(sandbox)
    end
  end

  describe "create_sandbox/3 with a cache" do
    setup do
      cache = %{
        volume_id: Ecto.UUID.generate(),
        scope: String.duplicate("a", 64),
        generation: 3,
        base_generation: 7,
        image_digest: String.duplicate("b", 40),
        content_digest: String.duplicate("c", 64)
      }

      expect(Capacity, :place, fn _sandbox -> {:ok, "node-a"} end)
      %{account: account_fixture(), cache: cache}
    end

    defp node_info(info), do: stub(Nodes, :lookup, fn "node-a" -> {:ok, self(), info} end)

    test "grants it on a node that accepts grants, attaches it to template creates and holds the master", %{
      account: account,
      cache: cache
    } do
      node_info(%{cache_grants: true, cache_drive_in_template: true})
      expect(VolumeAffinities, :holds_volume?, fn "node-a", scope -> scope == cache.scope end)

      expect(Nodes, :call, fn "node-a", "create", args, _opts ->
        refute Map.has_key?(args, :cache)

        assert args.cache_grant == %{
                 id: args.sandbox_id,
                 scope: cache.scope,
                 base_generation: 7,
                 image_digest: cache.image_digest,
                 content_digest: cache.content_digest
               }

        {:ok, %{"boot_ms" => 170}}
      end)

      assert {:ok, sandbox} = Sandboxes.create_sandbox(account, %{}, cache: cache)
      assert sandbox.cache_volume_id == cache.volume_id
      assert sandbox.cache_generation == 7
    end

    test "records the generation the node attached when it lent an older one", %{account: account, cache: cache} do
      node_info(%{cache_grants: true, cache_drive_in_template: true})
      stub(VolumeAffinities, :holds_volume?, fn "node-a", _scope -> true end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{"boot_ms" => 170, "cache_generation" => 5}} end)

      assert {:ok, sandbox} = Sandboxes.create_sandbox(account, %{}, cache: cache)
      assert sandbox.cache_volume_id == cache.volume_id
      assert sandbox.cache_generation == 5
    end

    test "creates without it where the node cannot attach it", %{account: account, cache: cache} do
      # The node's shape snapshots carry no placeholder, so a template create
      # would have to cold boot.
      node_info(%{cache_grants: true, cache_drive_in_template: false})
      stub(VolumeAffinities, :holds_volume?, fn _node, _scope -> true end)

      expect(Nodes, :call, fn "node-a", "create", args, _opts ->
        refute Map.has_key?(args, :cache_grant)
        refute Map.has_key?(args, :cache)
        {:ok, %{"boot_ms" => 170}}
      end)

      assert {:ok, sandbox} = Sandboxes.create_sandbox(account, %{}, cache: cache)
      assert is_nil(sandbox.cache_volume_id)
      assert is_nil(sandbox.cache_generation)
    end

    test "retries without it when the node no longer holds the master", %{account: account, cache: cache} do
      node_info(%{cache_grants: true, cache_drive_in_template: true})
      stub(VolumeAffinities, :holds_volume?, fn _node, _scope -> true end)

      expect(Nodes, :call, 2, fn "node-a", "create", args, _opts ->
        if Map.has_key?(args, :cache_grant),
          do: {:error, "invalid cache image: this node holds no copy of the granted cache"},
          else: {:ok, %{"boot_ms" => 1200}}
      end)

      assert {:ok, sandbox} = Sandboxes.create_sandbox(account, %{}, cache: cache)
      assert sandbox.state == :running
      assert is_nil(sandbox.cache_volume_id)
    end

    test "does not retry other create failures without it", %{account: account, cache: cache} do
      node_info(%{cache_grants: true, cache_drive_in_template: true})
      stub(VolumeAffinities, :holds_volume?, fn _node, _scope -> true end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:error, "jailer exited with status 1"} end)

      assert {:error, "jailer exited with status 1"} = Sandboxes.create_sandbox(account, %{}, cache: cache)
    end
  end

  describe "lifetimes" do
    defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

    test "extend/2 starts the lifetime again, with a new length when given, up to a day" do
      sandbox = sandbox_fixture(state: :running, lifetime_seconds: 7200, expires_at: ago(60))

      assert {:ok, %Sandbox{lifetime_seconds: 7200, expires_at: expires_at}} = Sandboxes.extend(sandbox, nil)
      assert_in_delta DateTime.diff(expires_at, DateTime.utc_now()), 7200, 5

      assert {:ok, %Sandbox{lifetime_seconds: 86_400, expires_at: expires_at}} = Sandboxes.extend(sandbox, 86_400)
      assert_in_delta DateTime.diff(expires_at, DateTime.utc_now()), 86_400, 5

      assert {:error, %Ecto.Changeset{}} = Sandboxes.extend(sandbox, 86_401)
      assert %Sandbox{lifetime_seconds: 86_400} = Repo.reload!(sandbox)
    end

    test "extend/2 refuses a sandbox an integration owns" do
      orb = sandbox_fixture(state: :running, amp_orb_id: "orb-1")
      assert {:error, :no_lifetime} = Sandboxes.extend(orb, 3600)
    end

    test "expire_sandboxes/0 pauses expired running sandboxes and leaves the rest alone" do
      account = account_fixture()
      expired = sandbox_fixture(account: account, node_name: "node-a", lifetime_seconds: 300, expires_at: ago(10))
      live = sandbox_fixture(account: account, node_name: "node-a", lifetime_seconds: 300, expires_at: ago(-600))
      unbounded = sandbox_fixture(account: account, node_name: "node-a")
      # Integrations own these, even with a stray expiry.
      orb = sandbox_fixture(account: account, node_name: "node-a", amp_orb_id: "orb-1", expires_at: ago(10))

      expired_id = expired.id

      expect(Nodes, :call, fn "node-a", "pause", %{sandbox_id: ^expired_id}, _opts -> {:ok, %{}} end)

      Sandboxes.expire_sandboxes()

      assert %Sandbox{state: :paused} = Repo.reload!(expired)
      for sandbox <- [live, unbounded, orb], do: assert(%Sandbox{state: :running} = Repo.reload!(sandbox))
    end

    test "expire_sandboxes/0 cancels a running command with a note, pauses, and a read does not resume it" do
      account = account_fixture()
      busy = sandbox_fixture(account: account, node_name: "node-a", lifetime_seconds: 300, expires_at: ago(10))

      command =
        Repo.insert!(%SandboxCommand{
          id: Ecto.UUID.generate(),
          sandbox_id: busy.id,
          account_id: account.id,
          command: "xcodebuild",
          status: :running,
          deadline_at: DateTime.truncate(ago(-3600), :second)
        })

      busy_id = busy.id
      command_id = command.id

      expect(Nodes, :call, 2, fn
        "node-a", "exec", %{sandbox_id: ^busy_id, env: %{"TUIST_COMMAND_ID" => ^command_id} = env}, _opts ->
          assert env["TUIST_REASON"] == "cancelled"
          assert env["TUIST_NOTE"] =~ "lifetime ended"
          {:ok, %{"exit_code" => 0}}

        "node-a", "pause", %{sandbox_id: ^busy_id}, _opts ->
          {:ok, %{}}
      end)

      Sandboxes.expire_sandboxes()

      assert %Sandbox{state: :paused} = paused = Repo.reload!(busy)
      assert %SandboxCommand{status: :cancelled} = Repo.reload!(command)

      # The client's next read answers from the row instead of resuming the sandbox.
      reject(&Nodes.call/4)
      assert {:ok, %{status: "cancelled", complete: true}} = Tuist.Sandboxes.Commands.read(paused, command_id)
    end

    test "expire_sandboxes/0 archives an expired paused Mac once its host evicted it" do
      paused_at = ago(120)

      evicted =
        sandbox_fixture(
          platform: :darwin,
          state: :paused,
          paused_at: paused_at,
          resident: false,
          expires_at: ago(60),
          lifetime_seconds: 300
        )

      resident =
        sandbox_fixture(
          platform: :darwin,
          state: :paused,
          paused_at: paused_at,
          resident: true,
          expires_at: ago(60),
          lifetime_seconds: 300
        )

      reject(&Nodes.call/4)
      Sandboxes.expire_sandboxes()

      assert_enqueued(worker: ArchiveSandboxesWorker, args: %{sandbox_id: evicted.id})
      refute_enqueued(worker: ArchiveSandboxesWorker, args: %{sandbox_id: resident.id})
    end

    test "a resume starts a new lifetime" do
      sandbox =
        sandbox_fixture(
          state: :paused,
          node_name: "node-a",
          paused_at: ago(600),
          lifetime_seconds: 3600,
          expires_at: ago(300)
        )

      stub(Capacity, :admit, fn sandbox -> {:ok, sandbox} end)
      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)

      assert {:ok, %Sandbox{state: :running, expires_at: expires_at}} = Sandboxes.resume(sandbox)
      assert_in_delta DateTime.diff(expires_at, DateTime.utc_now()), 3600, 5
    end

    test "a Mac's guest CPU does not extend its session, but an Orb's does" do
      quiet_since = DateTime.truncate(ago(100), :second)

      mac =
        sandbox_fixture(
          platform: :darwin,
          state: :running,
          node_name: "mac-a",
          guest_cpu_ms: 1000,
          last_active_at: quiet_since
        )

      orb =
        sandbox_fixture(
          platform: :darwin,
          state: :running,
          node_name: "mac-a",
          amp_orb_id: "orb-1",
          guest_cpu_ms: 1000,
          last_active_at: quiet_since
        )

      report =
        for sandbox <- [mac, orb], do: %{"id" => sandbox.id, "state" => "running", "cpu_ms" => 90_000, "resident" => true}

      assert :ok = Sandboxes.reconcile_node_report("mac-a", %{"sandboxes" => report})

      assert %Sandbox{last_active_at: ^quiet_since} = Repo.reload!(mac)
      assert %Sandbox{last_active_at: active_at} = Repo.reload!(orb)
      assert DateTime.after?(active_at, quiet_since)
    end
  end
end
