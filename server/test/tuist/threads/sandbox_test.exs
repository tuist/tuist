defmodule Tuist.Threads.SandboxTest do
  # The adapter against the real `Commands` guest scripts: the node's exec
  # runs them with the host's bash, `/workspace` and `$HOME` in a temporary
  # directory standing in for the VM.
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Condukt.Sandbox
  alias Condukt.Tools.Bash
  alias Condukt.Tools.Bash.Exited
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.SandboxCommand
  alias Tuist.Threads.ExitWatchWorker
  alias Tuist.Threads.Sandbox, as: ThreadSandbox

  setup do
    {:ok, root} = Briefly.create(directory: true)
    File.mkdir_p!(Path.join(root, "workspace/repository"))
    File.mkdir_p!(Path.join(root, "home"))

    stub(Nodes, :call, fn "node-a", "exec", args, opts -> guest_exec(root, args, opts) end)

    record = sandbox_fixture(state: :running, node_name: "node-a")
    record = Repo.update!(Ecto.Changeset.change(record, residency_work_id: "threads:run:1"))

    {:ok, sandbox} =
      Sandbox.new(ThreadSandbox, sandbox_id: record.id, account_id: record.account_id, residency: "threads:run:1")

    %{root: root, record: record, sandbox: sandbox}
  end

  test "refuses a sandbox of another account", %{record: record} do
    assert {:error, :sandbox_not_found} = Sandbox.new(ThreadSandbox, sandbox_id: record.id, account_id: -1)
  end

  test "files, edits, glob, grep and exec work relative to the repository", %{sandbox: sandbox, root: root} do
    # Binary content and a size that crosses an environment part.
    content = :crypto.strong_rand_bytes(100_000)
    assert :ok = Sandbox.write(sandbox, "dir/blob.bin", content)
    assert File.read!(Path.join(root, "workspace/repository/dir/blob.bin")) == content
    assert {:ok, ^content} = Sandbox.read(sandbox, "dir/blob.bin")
    assert {:error, :enoent} = Sandbox.read(sandbox, "missing")

    assert :ok = Sandbox.write(sandbox, "a.txt", "one two two\n")
    assert {:ok, %{occurrences: 2}} = Sandbox.edit(sandbox, "a.txt", "two", "three")
    assert {:ok, %{occurrences: 1, content: "one 2 two\n"}} = Sandbox.edit(sandbox, "a.txt", "two two", "2 two")

    assert {:ok, ["a.txt", "dir/blob.bin"]} = Sandbox.glob(sandbox, "**/*.*")

    # The tools also name files absolutely, or from `./`, inside the checkout.
    assert {:ok, "one 2 two\n"} = Sandbox.read(sandbox, "/workspace/repository/a.txt")
    assert {:ok, "one 2 two\n"} = Sandbox.read(sandbox, "./a.txt")
    assert {:ok, ["dir/blob.bin"]} = Sandbox.glob(sandbox, "**/*.bin", cwd: "/workspace/repository/")

    assert {:ok, [%{path: "a.txt", line_number: 1, line: "one 2 two"}]} =
             Sandbox.grep(sandbox, "TWO$", case_sensitive: false, glob: "*.txt")

    assert {:ok, %{output: "out\nerr\n", exit_code: 3}} =
             Sandbox.exec(sandbox, "echo out; echo err >&2; exit 3", env: [{"X", "1"}])
  end

  test "tool paths and payloads are bounded to the checkout", %{sandbox: sandbox} do
    reject(Nodes, :call, 4)

    for path <- ["/etc/passwd", "/workspace/repository/../secret", "../secret", ".git/config", "a/../secret", "a//b", ""] do
      assert {:error, :invalid_path} = Sandbox.read(sandbox, path)
      assert {:error, :invalid_path} = Sandbox.write(sandbox, path, "x")
      assert {:error, :invalid_path} = Sandbox.edit(sandbox, path, "a", "b")
      if path != "", do: assert({:error, :invalid_path} = Sandbox.glob(sandbox, "*", cwd: path))
      if path != "", do: assert({:error, :invalid_path} = Sandbox.grep(sandbox, "x", path: path))
    end

    assert {:error, :too_large} = Sandbox.write(sandbox, "big", String.duplicate("x", 1024 * 1024 + 1))
  end

  test "file operations reject symlink parents and final symlinks without truncation",
       %{sandbox: sandbox, root: root} do
    repository = Path.join(root, "workspace/repository")
    File.write!(Path.join(root, "workspace/secret"), "preserve")
    File.ln_s!(Path.join(root, "workspace"), Path.join(repository, "link"))
    File.ln_s!(Path.join(root, "workspace/secret"), Path.join(repository, "file"))
    File.mkdir_p!(Path.join(repository, ".git"))
    File.write!(Path.join(repository, ".git/config"), "preserve")

    for path <- ["link/secret", "file", "link/new"] do
      assert {:error, _reason} = Sandbox.write(sandbox, path, "overwrite")
      assert {:error, _reason} = Sandbox.read(sandbox, path)
      assert {:error, _reason} = Sandbox.edit(sandbox, path, "preserve", "overwrite")
    end

    assert File.read!(Path.join(root, "workspace/secret")) == "preserve"
    refute File.exists?(Path.join(root, "workspace/new"))

    # Glob and grep list the links by name but never look through them; a
    # symlinked base fails as O_DIRECTORY | O_NOFOLLOW does, with ENOTDIR.
    assert {:ok, ["file", "link"]} = Sandbox.glob(sandbox, "**/*")
    assert {:ok, []} = Sandbox.grep(sandbox, "preserve")
    assert {:error, :enotdir} = Sandbox.glob(sandbox, "*", cwd: "link")
    assert {:error, :enotdir} = Sandbox.grep(sandbox, "preserve", path: "link")

    assert :ok = Sandbox.write(sandbox, "normal", "old")
    assert {:ok, %{occurrences: 1}} = Sandbox.edit(sandbox, "normal", "old", "new")
    assert File.read!(Path.join(repository, "normal")) == "new"
  end

  test "a process runs as a Commands command under the run's residency, takes stdin, and stops",
       %{sandbox: sandbox, record: record} do
    id = "condukt-bash:session:call_1"
    assert :ok = Sandbox.start_process(sandbox, id, "echo started; cat; echo err >&2; exit 4", stdin: true)
    assert {:error, :already_started} = Sandbox.start_process(sandbox, id, "true")

    command = Repo.get!(SandboxCommand, ThreadSandbox.command_id(id))
    assert command.sandbox_id == record.id
    # The command joined the run's residency rather than taking `commands`.
    assert Repo.reload!(record).residency_work_id == "threads:run:1"

    assert {:ok, %{output: "started\n", offset: 8, status: :running}} =
             Sandbox.read_process(sandbox, id, 0, wait: 5_000)

    assert :ok = Sandbox.write_process(sandbox, id, "in\n", offset: 0)
    assert :ok = Sandbox.write_process(sandbox, id, "in\n", offset: 0)
    assert {:error, :offset_mismatch} = Sandbox.write_process(sandbox, id, "x", offset: 1)
    assert :ok = Sandbox.write_process(sandbox, id, "", close: true)

    # stderr is folded into the one log the model reads.
    assert {:ok, %{output: "in\nerr\n", size: 15, status: {:exited, 4}}} = await_exit(sandbox, id, 40)
    assert {:ok, %{output: "", size: 15}} = Sandbox.read_process(sandbox, id, 0, max_bytes: 0)

    assert :ok = Sandbox.stop_process(sandbox, id)
    refute Repo.get(SandboxCommand, ThreadSandbox.command_id(id))
    assert :ok = Sandbox.stop_process(sandbox, id)
  end

  test "Condukt's Bash runs a command through it and returns its result", %{sandbox: sandbox} do
    context = %{sandbox: sandbox, session_id: "s", tool_call_id: "call_1", agent: self(), turn_ref: make_ref()}

    assert {:ok, "hello\n\n\n(exit code: 2)"} =
             Bash.call(%{"command" => "echo hello; exit 2"}, context)
  end

  test "watch_process has an Oban job deliver the exit to the session by id", %{sandbox: sandbox, record: record} do
    id = "condukt-bash:session:call_2"
    assert :ok = Sandbox.start_process(sandbox, id, "exit 0")
    target = %{session_id: "session", signal: Exited, key: "bash:call_2"}

    assert :ok = Sandbox.watch_process(sandbox, id, target)

    assert_enqueued(
      worker: ExitWatchWorker,
      args: %{
        sandbox_id: record.id,
        account_id: record.account_id,
        command_id: ThreadSandbox.command_id(id),
        session_id: "session",
        signal: "Elixir.Condukt.Tools.Bash.Exited",
        key: "bash:call_2"
      }
    )

    test_pid = self()

    expect(Condukt, :signal, fn "session", Exited, "bash:call_2", status ->
      send(test_pid, {:signalled, status})
      :ok
    end)

    job_args = %{
      "sandbox_id" => record.id,
      "account_id" => record.account_id,
      "command_id" => ThreadSandbox.command_id(id),
      "session_id" => "session",
      "signal" => "Elixir.Condukt.Tools.Bash.Exited",
      "key" => "bash:call_2"
    }

    assert :ok = perform_job(ExitWatchWorker, job_args)
    assert_received {:signalled, {:exited, 0}}
  end

  test "a call that parks on a command again replaces the key its exit watch delivers under",
       %{sandbox: sandbox} do
    id = "condukt-bash:session:call_4"
    assert :ok = Sandbox.start_process(sandbox, id, "sleep 30")
    assert :ok = Sandbox.watch_process(sandbox, id, %{session_id: "session", signal: Exited, key: "bash:call_4"})
    assert :ok = Sandbox.watch_process(sandbox, id, %{session_id: "session", signal: Exited, key: "bash:call_4:2"})

    assert [%{args: %{"key" => "bash:call_4:2"}}] = all_enqueued(worker: ExitWatchWorker)
  end

  test "a process's timeout is cut to end by the run's commands_end_by", %{record: record} do
    {:ok, sandbox} =
      Sandbox.new(ThreadSandbox,
        sandbox_id: record.id,
        account_id: record.account_id,
        residency: "threads:run:1",
        commands_end_by: System.os_time(:millisecond) + 30_000
      )

    id = "condukt-bash:session:call_3"
    assert :ok = Sandbox.start_process(sandbox, id, "exit 0", timeout: 600_000)

    deadline_at = Repo.get!(SandboxCommand, ThreadSandbox.command_id(id)).deadline_at
    assert DateTime.diff(deadline_at, DateTime.utc_now(), :second) in 28..32

    # Once the run is about to end, nothing new starts.
    {:ok, ending} =
      Sandbox.new(ThreadSandbox,
        sandbox_id: record.id,
        account_id: record.account_id,
        residency: "threads:run:1",
        commands_end_by: System.os_time(:millisecond) + 500
      )

    assert {:error, :run_ending} = Sandbox.start_process(ending, "condukt-bash:session:call_5", "exit 0", [])
    refute Repo.get(SandboxCommand, ThreadSandbox.command_id("condukt-bash:session:call_5"))
  end

  test "activity takes the run's residency again and gives it back", %{sandbox: sandbox, record: record} do
    Repo.update!(Ecto.Changeset.change(record, residency_work_id: nil))
    assert :ok = Sandbox.activity(sandbox, :active)
    assert Repo.reload!(record).residency_work_id == "threads:run:1"
    assert :ok = Sandbox.activity(sandbox, :active)
    assert :ok = Sandbox.activity(sandbox, :idle)
    assert Repo.reload!(record).residency_work_id == nil
  end

  test "command ids are stable UUIDs per process id" do
    assert ThreadSandbox.command_id("a") == ThreadSandbox.command_id("a")
    refute ThreadSandbox.command_id("a") == ThreadSandbox.command_id("b")
    assert {:ok, _} = Ecto.UUID.cast(ThreadSandbox.command_id("a"))
  end

  # Output past offset 8 is already there, so the long-poll returns at once:
  # pause between reads instead.
  defp await_exit(sandbox, id, attempts) do
    case Sandbox.read_process(sandbox, id, 8, wait: 2_000) do
      {:ok, %{status: :running}} when attempts > 0 ->
        Process.sleep(250)
        await_exit(sandbox, id, attempts - 1)

      other ->
        other
    end
  end

  # Runs one exec as the guest agent would: in its cwd, with its env, the
  # VM's paths under `root`, stdout and stderr streamed apart.
  defp guest_exec(root, args, opts) do
    err = Path.join(root, "stderr-#{System.unique_integer([:positive])}")
    cwd = String.replace_prefix(args.cwd, "/workspace", Path.join(root, "workspace"))

    [program | rest] =
      Enum.map(args.cmd, &String.replace(&1, "/workspace/repository", Path.join(root, "workspace/repository")))

    env =
      args.env
      |> Map.new(fn {key, value} -> {key, String.replace_prefix(value, "/workspace", Path.join(root, "workspace"))} end)
      |> Map.merge(%{"HOME" => Path.join(root, "home"), "CONDUKT_TEST_ERR" => err})

    {stdout, code} =
      System.cmd("bash", ["-c", ~s(exec 2>"$CONDUKT_TEST_ERR"; exec "$@"), "guest", program | rest],
        cd: cwd,
        env: Enum.to_list(env)
      )

    stderr = File.read!(err)
    opts[:on_stream].({:stdout, stdout})
    opts[:on_stream].({:stderr, stderr})
    {:ok, %{"exit_code" => code}}
  end
end
