defmodule Tuist.SandboxesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.PauseSandboxWorker

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
        assert args.vcpus == 2
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
    end

    test "applies the requested shape" do
      account = account_fixture()

      expect(Capacity, :place, fn %{template: "xcode"} -> {:ok, "node-a"} end)

      expect(Nodes, :call, fn "node-a",
                              "create",
                              %{template: "xcode", vcpus: 8, memory_mb: 16_384, workspace_gb: 40},
                              _ ->
        {:ok, %{}}
      end)

      assert {:ok, %Sandbox{vcpus: 8, memory_mb: 16_384, workspace_gb: 40, template: "xcode"}} =
               Sandboxes.create_sandbox(account, %{template: "xcode", vcpus: 8, memory_mb: 16_384, workspace_gb: 40})
    end

    test "marks the sandbox as errored when no node can host it" do
      account = account_fixture()
      expect(Capacity, :place, fn _ -> {:error, :no_node} end)

      assert {:error, :no_node} = Sandboxes.create_sandbox(account, %{})

      assert [%Sandbox{state: :error, node_name: nil, error_message: message}] = Sandboxes.list_sandboxes(account)
      assert message =~ "no node"
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
    test "pause/1 snapshots a running sandbox" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      sandbox_id = sandbox.id

      expect(Nodes, :call, fn "node-a", "pause", %{sandbox_id: ^sandbox_id}, _opts ->
        {:ok, %{"snapshot_ms" => 300, "mem_bytes" => 1024}}
      end)

      assert {:ok, %Sandbox{state: :paused, paused_at: %DateTime{}}} = Sandboxes.pause(sandbox)
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
    end
  end

  describe "reconcile_node_report/2" do
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
      missing = sandbox_fixture(state: :paused, node_name: "node-a", residency_work_id: "work_9", residency_epoch: 1)
      untouched = sandbox_fixture(state: :creating, node_name: nil)
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
    end

    test "leaves a sandbox being deleted alone" do
      deleting = sandbox_fixture(state: :deleted, node_name: "node-a")
      reject(&Nodes.call/4)

      assert :ok =
               Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => [%{"id" => deleting.id, "state" => "running"}]})

      assert %Sandbox{state: :deleted} = Repo.reload!(deleting)
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

    test "errors a creating sandbox the node never got once it has been stuck, and leaves a fresh one alone" do
      stuck = [state: :creating, node_name: "node-a"] |> sandbox_fixture() |> backdate(600)
      fresh = sandbox_fixture(state: :creating, node_name: "node-a")
      resuming = sandbox_fixture(state: :resuming, node_name: "node-a")

      Sandboxes.reconcile_node_report("node-a", %{"sandboxes" => []})

      assert %Sandbox{state: :error, error_message: "missing on node"} = Repo.reload!(stuck)
      assert %Sandbox{state: :creating} = Repo.reload!(fresh)
      assert %Sandbox{state: :error, error_message: "missing on node"} = Repo.reload!(resuming)
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
    test "refuses a create past the account's live sandbox limit" do
      account = account_fixture()

      for _ <- 1..Sandboxes.max_live_sandboxes_per_account(),
          do: sandbox_fixture(account: account, state: :paused, node_name: "node-a")

      reject(&Capacity.place/1)
      assert {:error, :sandbox_limit} = Sandboxes.create_sandbox(account, %{})
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
end
