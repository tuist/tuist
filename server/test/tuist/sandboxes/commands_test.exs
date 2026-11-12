defmodule Tuist.Sandboxes.CommandsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand
  alias Tuist.Sandboxes.Workers.CommandWatchWorker
  alias Tuist.Sandboxes.Workers.EndLeaseWorker
  alias Tuist.Sandboxes.Workers.PauseSandboxWorker

  # The guest's read answer: a header line, the stdout chunk on stdout and
  # the stderr chunk on stderr.
  defp guest_read(header, stdout, stderr \\ "") do
    fn "node-a", "exec", _args, opts ->
      opts[:on_stream].({:stdout, header <> "\n" <> stdout})
      if stderr != "", do: opts[:on_stream].({:stderr, stderr})
      {:ok, %{"exit_code" => 0}}
    end
  end

  defp started(_args \\ nil), do: fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end

  defp stdin_from_env(env) do
    0..(String.to_integer(env["TUIST_STDIN_PARTS"]) - 1)//1
    |> Enum.map_join(&env["TUIST_STDIN_DATA_#{&1}"])
    |> Base.decode64!()
  end

  defp running_command(sandbox, attrs \\ []) do
    Repo.insert!(%SandboxCommand{
      id: Ecto.UUID.generate(),
      sandbox_id: sandbox.id,
      account_id: sandbox.account_id,
      command: Keyword.get(attrs, :command, "true"),
      stdin: Keyword.get(attrs, :stdin, false),
      deadline_at: DateTime.add(DateTime.utc_now(:second), 3600)
    })
  end

  describe "start/2" do
    test "runs several commands under one shared residency" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      sandbox_id = sandbox.id

      expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
        assert env["TUIST_COMMAND"] == "xcodebuild -scheme App"
        assert env["TUIST_STDIN"] == "0"
        assert env["DEVELOPER_DIR"] == "/Applications/Xcode.app"
        {:ok, %{"exit_code" => 0}}
      end)

      assert {:ok, %{id: first, status: "running"}} =
               Commands.start(sandbox, %{
                 command: "xcodebuild -scheme App",
                 env: %{"DEVELOPER_DIR" => "/Applications/Xcode.app"}
               })

      assert %Sandbox{residency_work_id: "commands"} = Repo.reload!(sandbox)

      expect(Nodes, :call, started())
      assert {:ok, %{id: second}} = Commands.start(Repo.reload!(sandbox), %{command: "tail -f log"})

      assert sandbox |> Commands.list() |> Enum.map(& &1.id) |> Enum.sort() == Enum.sort([first, second])
      enqueued = all_enqueued(worker: CommandWatchWorker)
      assert Enum.all?(enqueued, &(&1.args["sandbox_id"] == sandbox_id))
      assert enqueued |> Enum.map(& &1.args["command_id"]) |> Enum.sort() == Enum.sort([first, second])
    end

    test "answers a request sent again with the same id with the command it started" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      id = Ecto.UUID.generate()
      expect(Nodes, :call, started())

      assert {:ok, %{id: ^id}} = Commands.start(sandbox, %{command: "make", id: id})
      assert {:ok, %{id: ^id, status: "running"}} = Commands.start(Repo.reload!(sandbox), %{command: "make", id: id})

      assert sandbox |> Commands.list() |> Enum.map(& &1.id) == [id]
      assert {:error, :invalid_command} = Commands.start(sandbox, %{command: "make", id: "not-a-uuid"})
    end

    test "never stores the environment" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      expect(Nodes, :call, started())

      assert {:ok, %{id: id}} = Commands.start(sandbox, %{command: "deploy", env: %{"TOKEN" => "s3cr3t"}})
      refute inspect(Repo.get!(SandboxCommand, id)) =~ "s3cr3t"
    end

    test "quotes argv so the shell does not interpret it" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")

      expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
        assert env["TUIST_COMMAND"] == ~S(exec 'printf' '%s\n' 'it'\''s $HOME')
        {:ok, %{"exit_code" => 0}}
      end)

      assert {:ok, _command} = Commands.start(sandbox, %{command: "printf", args: ["%s\\n", "it's $HOME"]})
    end

    test "refuses invalid environment names before touching the sandbox" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      reject(&Nodes.call/4)

      assert {:error, :invalid_command} = Commands.start(sandbox, %{command: "true", env: %{"A=B" => "x"}})
      assert {:error, :invalid_command} = Commands.start(sandbox, %{command: "true", args: [1]})
      assert {:error, :invalid_command} = Commands.start(sandbox, %{command: ""})
      assert Repo.all(SandboxCommand) == []
    end

    test "is refused while an agent turn holds the sandbox" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "amp:orb")
      reject(&Nodes.call/4)

      assert {:error, :busy} = Commands.start(sandbox, %{command: "true"})
      assert Repo.all(SandboxCommand) == []
      assert %Sandbox{residency_work_id: "amp:orb"} = Repo.reload!(sandbox)
    end

    test "waits out a pause the start raced with, then resumes the sandbox and starts the command" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")

      # The idle pause reached the node first; by the time the start retries,
      # the row says paused.
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts ->
        sandbox |> Ecto.Changeset.change(state: :paused) |> Repo.update!()
        {:error, "sandbox is being paused: #{sandbox.id}"}
      end)

      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, started())

      assert {:ok, %{id: id, status: "running"}} = Commands.start(sandbox, %{command: "true"})
      assert %Sandbox{state: :running, residency_work_id: "commands"} = Repo.reload!(sandbox)
      assert [%SandboxCommand{id: ^id}] = Repo.all(SandboxCommand)
    end

    test "adopts a pause the node made whose caller died, then resumes the sandbox and starts the command" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      paused = {:error, "sandbox is not running: #{sandbox.id} is paused"}

      # The launch, then the check under the sandbox's lock, both meet the
      # paused VM while the row still says running.
      expect(Nodes, :call, 2, fn "node-a", "exec", _args, _opts -> paused end)
      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, started())

      assert {:ok, %{id: id, status: "running"}} = Commands.start(sandbox, %{command: "true"})
      assert %Sandbox{state: :running, residency_work_id: "commands"} = Repo.reload!(sandbox)
      assert [%SandboxCommand{id: ^id}] = Repo.all(SandboxCommand)
    end

    test "keeps a running sandbox's row when the node no longer says it is paused" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")

      expect(Nodes, :call, fn "node-a", "exec", _args, _opts ->
        {:error, "sandbox is not running: #{sandbox.id} is paused"}
      end)

      # A resume on another replica won the race: the VM runs again.
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:ok, %{"exit_code" => 0}} end)
      expect(Nodes, :call, started())

      assert {:ok, %{status: "running"}} = Commands.start(sandbox, %{command: "true"})
      assert %Sandbox{state: :running, paused_at: nil} = Repo.reload!(sandbox)
    end

    test "gives the sandbox back when the command cannot start" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")

      expect(Nodes, :call, fn "node-a", "exec", _args, opts ->
        opts[:on_stream].({:stderr, "setsid: Operation not permitted\n"})
        {:ok, %{"exit_code" => 1}}
      end)

      assert {:error, "could not start the command: setsid: Operation not permitted"} =
               Commands.start(sandbox, %{command: "true"})

      assert %Sandbox{residency_work_id: nil} = Repo.reload!(sandbox)
      assert Repo.all(SandboxCommand) == []
      assert [] = all_enqueued(worker: CommandWatchWorker)
    end
  end

  describe "read/3" do
    test "stops a chunk before a split UTF-8 character and resumes from it" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "commands")
      command = running_command(sandbox)

      # "hé" is <<104, 195, 169>>; the guest's chunk ended after 195.
      expect(Nodes, :call, guest_read("running - 3 0 -", <<104, 195>>))

      assert {:ok, %{status: "running", stdout: "h", stdout_offset: 101, stderr_offset: 7, complete: false}} =
               Commands.read(sandbox, command.id, stdout_offset: 100, stderr_offset: 7)
    end

    test "keeps the residency until the last command ends" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "commands")
      first = running_command(sandbox)
      second = running_command(sandbox)

      expect(Nodes, :call, guest_read("exited 2 4 3 -", "out\n", "err"))

      assert {:ok, %{status: "exited", exit_code: 2, stdout: "out\n", stderr: "err", complete: true}} =
               Commands.read(sandbox, first.id)

      assert %SandboxCommand{status: :exited, exit_code: 2, finished_at: %DateTime{}} = Repo.reload!(first)
      assert %Sandbox{residency_work_id: "commands"} = Repo.reload!(sandbox)

      expect(Nodes, :call, guest_read("exited 0 0 0 cancelled", ""))
      assert {:ok, %{status: "cancelled"}} = Commands.read(sandbox, second.id)
      assert %Sandbox{residency_work_id: nil} = Repo.reload!(sandbox)
      assert [_pause] = all_enqueued(worker: PauseSandboxWorker)
    end

    test "on a node shared with CI, pauses 20 seconds after the last command, and at once after other work" do
      Repo.insert!(%Tuist.Sandboxes.SandboxNode{
        name: "node-a",
        pod_name: "sandboxd-a",
        memory_limit_bytes: 1_073_741_824
      })

      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "commands")
      command = running_command(sandbox)

      expect(Nodes, :call, guest_read("exited 0 0 0 -", ""))
      assert {:ok, %{status: "exited"}} = Commands.read(sandbox, command.id)

      assert [%Oban.Job{scheduled_at: scheduled_at}] = all_enqueued(worker: PauseSandboxWorker)
      assert DateTime.diff(scheduled_at, DateTime.utc_now()) in 15..20

      other = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "amp:orb")
      assert {:ok, _} = Sandboxes.end_residency(other.id, "amp:orb")

      assert %Oban.Job{scheduled_at: scheduled_at} =
               Enum.find(all_enqueued(worker: PauseSandboxWorker), &(&1.args["sandbox_id"] == other.id))

      assert DateTime.diff(scheduled_at, DateTime.utc_now()) <= 0
    end

    test "leaves another residency alone" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "amp:orb")
      command = running_command(sandbox)

      expect(Nodes, :call, guest_read("exited 143 0 0 timeout", ""))
      assert {:ok, %{status: "timed_out", exit_code: 143}} = Commands.read(sandbox, command.id)
      assert %Sandbox{residency_work_id: "amp:orb"} = Repo.reload!(sandbox)
    end

    test "answers not found for another sandbox's command" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      other = running_command(sandbox_fixture(state: :running, node_name: "node-a"))
      reject(&Nodes.call/4)

      assert {:error, :not_found} = Commands.read(sandbox, other.id)
      assert {:error, :not_found} = Commands.read(sandbox, "not-a-uuid")
    end
  end

  describe "write_stdin/4" do
    test "refuses a command started without stdin" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      command = running_command(sandbox)
      reject(&Nodes.call/4)

      assert {:error, :stdin_not_attached} = Commands.write_stdin(sandbox, command.id, "y\n", false)
    end

    test "appends the data and closes stdin" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      command = running_command(sandbox, stdin: true)

      expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
        assert stdin_from_env(env) == <<0, 255, ?\n>>
        assert env["TUIST_STDIN_CLOSE"] == "1"
        {:ok, %{"exit_code" => 0}}
      end)

      assert {:ok, %{stdin: true}} = Commands.write_stdin(sandbox, command.id, <<0, 255, ?\n>>, true)
    end

    test "splits a full write into environment strings Linux accepts" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      command = running_command(sandbox, stdin: true)
      data = :crypto.strong_rand_bytes(Commands.max_stdin_bytes())

      expect(Nodes, :call, fn "node-a", "exec", %{env: env}, _opts ->
        # MAX_ARG_STRLEN: each `NAME=value` string, with its terminating NUL, must fit in 128 KiB.
        assert Enum.all?(env, fn {name, value} -> byte_size(name) + byte_size(value) + 2 <= 128 * 1024 end)
        assert stdin_from_env(env) == data
        {:ok, %{"exit_code" => 0}}
      end)

      assert {:ok, %{stdin: true}} = Commands.write_stdin(sandbox, command.id, data, false)
    end

    @tag :tmp_dir
    test "with offsets, appends a write sent again once and refuses one that does not continue stdin", %{
      tmp_dir: home
    } do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a")
      command = running_command(sandbox, stdin: true)
      dir = Path.join(home, ".cache/tuist/commands/#{command.id}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "stdin"), "")

      # Runs the real stdin script against the command's directory.
      stub(Nodes, :call, fn "node-a", "exec", %{cmd: ["/bin/bash", "-c", script], env: env}, _opts ->
        {_output, code} = System.cmd("/bin/bash", ["-c", script], env: Map.put(env, "HOME", home), stderr_to_stdout: true)
        {:ok, %{"exit_code" => code}}
      end)

      write = fn data, close?, offset -> Commands.write_stdin(sandbox, command.id, data, close?, offset) end

      assert {:ok, _} = write.("abc", false, 0)
      assert {:ok, _} = write.("abc", false, 0)
      assert {:error, :stdin_offset_mismatch} = write.("x", false, 1)
      assert {:ok, _} = write.("de", true, 3)
      assert {:ok, _} = write.("de", true, 3)
      assert {:error, :stdin_closed} = write.("f", false, 5)

      assert File.read!(Path.join(dir, "stdin")) == "abcde"
      assert File.exists?(Path.join(dir, "stdin_closed"))
    end
  end

  test "pause_idle/2 leaves a sandbox with running commands up" do
    sandbox = sandbox_fixture(state: :running, node_name: "node-a")
    running_command(sandbox)
    reject(&Nodes.call/4)

    assert {:ok, :skipped} = Sandboxes.pause_idle(sandbox.id)
  end

  describe "on macOS" do
    setup do
      grant = %{
        "allow" => true,
        "memory_bytes" => 24 * 1024 * 1024 * 1024,
        "cpu_milli" => 16_000,
        "slots" => 2,
        "node_uid" => "node-uid",
        "control_uid" => "control-uid",
        "observed_at" => DateTime.to_iso8601(DateTime.utc_now())
      }

      node = %{
        name: "mac-a",
        platform: "darwin",
        generation: "node-uid",
        control_uid: "control-uid",
        capacity: %{memory_bytes: 24 * 1024 * 1024 * 1024, cpus: 16},
        templates: [%{name: "macos", ready: true, tag: "image@sha256:abc"}],
        admission: grant
      }

      stub_grant(node, nil)
      %{node: node}
    end

    # CI holds the Mac's grant until `opens_at` (monotonic milliseconds).
    defp stub_grant(node, opens_at) do
      stub(Nodes, :lookup, fn "mac-a" ->
        open = is_nil(opens_at) or System.monotonic_time(:millisecond) >= opens_at
        {:ok, self(), %{node | admission: Map.put(node.admission, "allow", open)}}
      end)
    end

    defp mac(opts) do
      sandbox_fixture(
        Keyword.merge(
          [platform: :darwin, template: "macos", vcpus: 8, memory_mb: 8192, node_name: "mac-a", node_uid: "node-uid"],
          opts
        )
      )
    end

    defp on_mac(op, answer \\ {:ok, %{"exit_code" => 0}}) do
      fn "mac-a", ^op, args, _opts ->
        send(self(), {:node_call, op, args})
        answer
      end
    end

    test "leases the sandbox to the session when its last command ends" do
      sandbox = mac(state: :running, residency_work_id: "commands", last_active_at: DateTime.utc_now())
      command = running_command(sandbox)

      expect(Nodes, :call, fn "mac-a", "exec", _args, opts ->
        opts[:on_stream].({:stdout, "exited 0 0 0 -\n"})
        {:ok, %{"exit_code" => 0}}
      end)

      expect(Nodes, :call, on_mac("hold_residency", {:ok, %{}}))

      assert {:ok, %{status: "exited"}} = Commands.read(sandbox, command.id)

      # The host hold outlasts the lease, so only the server ends it.
      assert_received {:node_call, "hold_residency", %{work_id: "commands", hold_ms: 720_000}}
      assert %Sandbox{state: :running, residency_work_id: "commands"} = Repo.reload!(sandbox)
      assert [] = all_enqueued(worker: PauseSandboxWorker)
      assert [%Oban.Job{scheduled_at: ends_at}] = all_enqueued(worker: EndLeaseWorker)
      assert DateTime.diff(ends_at, DateTime.utc_now()) in 590..600
    end

    test "a command joins the lease while CI holds the Mac's grant", %{node: node} do
      sandbox = mac(state: :running, residency_work_id: "commands", last_active_at: DateTime.utc_now())
      stub_grant(node, System.monotonic_time(:millisecond) + 60_000)

      expect(Nodes, :call, on_mac("hold_residency", {:ok, %{}}))
      expect(Nodes, :call, on_mac("exec"))

      assert {:ok, %{status: "running"}} = Commands.start(sandbox, %{command: "xcodebuild"})
      # While a command runs, only a release or pause ends the host hold.
      assert_received {:node_call, "hold_residency", args}
      refute Map.has_key?(args, :hold_ms)
    end

    test "without a lease, a command waits in the request for CI to give the Mac's grant back", %{node: node} do
      sandbox = mac(state: :paused, resident: true, last_active_at: DateTime.utc_now())
      started = System.monotonic_time(:millisecond)
      # CI gives the grant back while the request waits.
      stub_grant(node, started + 1_500)

      expect(Nodes, :call, fn "mac-a", "resume", _args, _opts ->
        send(self(), {:resumed_after_ms, System.monotonic_time(:millisecond) - started})
        {:ok, %{"restore_ms" => 400}}
      end)

      expect(Nodes, :call, on_mac("hold_residency", {:ok, %{}}))
      expect(Nodes, :call, on_mac("exec"))

      assert {:ok, %{status: "running"}} = Commands.start(sandbox, %{command: "true"})
      assert_received {:resumed_after_ms, waited}
      assert waited in 1_500..3_000
      assert %Sandbox{state: :running, residency_work_id: "commands"} = Repo.reload!(sandbox)
    end

    test "ends the lease once the sandbox has been idle for its length, and keeps it otherwise" do
      busy = mac(state: :running, residency_work_id: "commands", last_active_at: DateTime.add(DateTime.utc_now(), -900))
      running_command(busy)
      recent = mac(state: :running, residency_work_id: "commands", last_active_at: DateTime.add(DateTime.utc_now(), -60))
      idle = mac(state: :running, residency_work_id: "commands", last_active_at: DateTime.add(DateTime.utc_now(), -601))

      expect(Nodes, :call, on_mac("release_residency", {:ok, %{}}))

      assert :ok = perform_job(EndLeaseWorker, %{sandbox_id: busy.id})
      assert :ok = perform_job(EndLeaseWorker, %{sandbox_id: recent.id})
      assert :ok = perform_job(EndLeaseWorker, %{sandbox_id: idle.id})

      assert %Sandbox{residency_work_id: "commands"} = Repo.reload!(busy)
      assert %Sandbox{residency_work_id: "commands"} = Repo.reload!(recent)
      assert %Sandbox{residency_work_id: nil} = Repo.reload!(idle)
      assert_received {:node_call, "release_residency", %{sandbox_id: idle_id, work_id: "commands"}}
      assert idle_id == idle.id

      # The idle one pauses at once; the recent one is checked again when
      # its lease would end.
      assert [%Oban.Job{args: %{"sandbox_id" => ^idle_id}, scheduled_at: pause_at}] =
               all_enqueued(worker: PauseSandboxWorker)

      assert DateTime.diff(pause_at, DateTime.utc_now()) <= 0
      assert [%Oban.Job{scheduled_at: ends_at}] = all_enqueued(worker: EndLeaseWorker, args: %{sandbox_id: recent.id})
      assert DateTime.diff(ends_at, DateTime.utc_now()) in 535..540
    end

    test "keep/1 leases a sandbox the API started, resuming it when its idle pause got there first" do
      sandbox = mac(state: :paused, resident: true, last_active_at: DateTime.utc_now())

      expect(Nodes, :call, on_mac("resume", {:ok, %{"restore_ms" => 400}}))
      expect(Nodes, :call, on_mac("hold_residency", {:ok, %{}}))

      assert {:ok, %Sandbox{state: :running, residency_work_id: "commands"}} = Commands.keep(sandbox)
      assert_received {:node_call, "hold_residency", %{hold_ms: 720_000}}
      assert [_lease_end] = all_enqueued(worker: EndLeaseWorker)

      # The idle pause the resume scheduled finds the session holding it.
      reject(&Nodes.call/4)
      assert [%Oban.Job{args: args}] = all_enqueued(worker: PauseSandboxWorker)
      assert :ok = perform_job(PauseSandboxWorker, args)
      assert %Sandbox{state: :running} = Repo.reload!(sandbox)
    end
  end

  describe "CommandWatchWorker" do
    test "kills a command still running past its deadline" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "commands")
      command = running_command(sandbox)

      expect(Nodes, :call, guest_read("running - 0 0 -", ""))

      expect(Nodes, :call, fn "node-a", "exec", %{env: %{"TUIST_REASON" => "timeout"}}, _opts ->
        {:ok, %{"exit_code" => 0}}
      end)

      args = %{sandbox_id: sandbox.id, command_id: command.id, deadline_ms: System.system_time(:millisecond) - 1}
      assert {:snooze, 5} = perform_job(CommandWatchWorker, args)
      assert %Sandbox{residency_work_id: "commands"} = Repo.reload!(sandbox)
    end

    test "records a command that is gone without a reader and gives the sandbox back" do
      sandbox = sandbox_fixture(state: :running, node_name: "node-a", residency_work_id: "commands")
      command = running_command(sandbox)
      expect(Nodes, :call, guest_read("lost - 0 0 -", ""))

      args = %{sandbox_id: sandbox.id, command_id: command.id, deadline_ms: System.system_time(:millisecond) + 60_000}
      assert :ok = perform_job(CommandWatchWorker, args)
      assert %SandboxCommand{status: :lost} = Repo.reload!(command)
      assert %Sandbox{residency_work_id: nil} = Repo.reload!(sandbox)
    end
  end
end
