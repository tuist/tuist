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
        assert Base.decode64!(env["TUIST_STDIN_DATA"]) == <<0, 255, ?\n>>
        assert env["TUIST_STDIN_CLOSE"] == "1"
        {:ok, %{"exit_code" => 0}}
      end)

      assert {:ok, %{stdin: true}} = Commands.write_stdin(sandbox, command.id, <<0, 255, ?\n>>, true)
    end
  end

  test "pause_idle/2 leaves a sandbox with running commands up" do
    sandbox = sandbox_fixture(state: :running, node_name: "node-a")
    running_command(sandbox)
    reject(&Nodes.call/4)

    assert {:ok, :skipped} = Sandboxes.pause_idle(sandbox.id)
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
