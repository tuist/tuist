defmodule Tuist.Sandboxes.ClaudeCodeSnapshotsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.GitHub
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.ClaudeCodeSnapshots
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand
  alias Tuist.Sandboxes.Workers.BuildRepositorySnapshotWorker
  alias Tuist.VCS

  @setup_script "mise install && mix compile\n"

  setup do
    account = account_fixture()

    agent_environment =
      agent_environment_fixture(
        account: account,
        kind: :claude_code,
        anthropic_environment_id: "ccpool_01linux",
        setup_script: @setup_script
      )

    test_pid = self()
    stub(Tuist.Environment, :runners_cluster_network_platforms, fn -> [] end)
    stub(Capacity, :place, fn _sandbox -> {:ok, "node-a"} end)
    stub(Capacity, :admit_turn, fn _sandbox, fun -> fun.() end)

    stub(Nodes, :connected_nodes, fn ->
      [%{name: "node-a", disk: %{}, templates: [%{name: "default", ready: true, tag: "sha-new", rootfs_bytes: 1}]}]
    end)

    installation = %{installation_id: "123", account_id: account.id}
    stub(VCS, :get_github_app_installation_for_account, fn _account_id -> {:ok, installation} end)

    stub(GitHub.App, :create_scoped_installation_token, fn ^installation, ["app"], %{contents: "read"} ->
      {:ok, %{token: "ghs_secret_token", expires_at: DateTime.utc_now()}}
    end)

    {:ok, build} =
      DiskSnapshots.start_build(agent_environment, "acme/app", ClaudeCodeSnapshots.setup_sha256(@setup_script))

    %{account: account, agent_environment: agent_environment, build: build, test_pid: test_pid}
  end

  # Answers the node's commands, reporting each to the test.
  defp stub_node(test_pid, exec_stdout \\ "") do
    stub(Nodes, :call, fn
      "node-a", "exec", args, opts ->
        send(test_pid, {:exec, args})
        if exec_stdout != "", do: opts[:on_stream].({:stdout, exec_stdout})
        {:ok, %{"exit_code" => 0}}

      "node-a", command, args, _opts ->
        send(test_pid, {String.to_atom(command), args})

        {:ok,
         case command do
           "create" -> %{"template_tag" => "sha-new"}
           "pause" -> %{"disks_synced" => true}
           _other -> %{}
         end}
    end)
  end

  defp node_calls do
    receive do
      call -> [call | node_calls()]
    after
      0 -> []
    end
  end

  defp finish_command(build, exit_code) do
    Repo.update_all(from(c in SandboxCommand, where: c.id == ^build.id),
      set: [status: :exited, exit_code: exit_code, finished_at: DateTime.utc_now(:second)]
    )
  end

  defp advance(build), do: perform_job(BuildRepositorySnapshotWorker, %{disk_snapshot_id: build.id})

  test "a build runs the script in a builder sandbox, saves its paused disks and deletes the builder", %{
    agent_environment: agent_environment,
    build: build,
    test_pid: test_pid
  } do
    stub_node(test_pid)

    assert {:snooze, 30} = advance(build)
    assert [{:create, create}, {:exec, start}] = node_calls()
    assert create.sandbox_id == build.id

    # One detached command clones as the runner's user and runs the script.
    # The token travels only in its environment, never in the recorded command.
    command = start.env["TUIST_COMMAND"]
    assert command =~ "git clone --quiet"
    assert command =~ "'/workspace/claude-code/acme/app' 'https://github.com/acme/app'"
    assert command =~ "'mise install && mix compile\n'"
    assert start.env["GIT_CONFIG_VALUE_0"] =~ "AUTHORIZATION: basic "
    refute command =~ Base.encode64("x-access-token:ghs_secret_token")
    assert start.env["TUIST_URL"] == Tuist.Environment.app_url()
    assert %SandboxCommand{command: ^command, status: :running} = Repo.get!(SandboxCommand, build.id)

    # The command still runs.
    assert {:snooze, 30} = advance(build)
    assert node_calls() == []

    finish_command(build, 0)
    assert :ok = advance(build)
    assert [{:pause, _pause}, {:save_disks, save}, {:delete, delete}] = node_calls()
    assert save.sandbox_id == build.id
    assert delete.sandbox_id == build.id

    assert %DiskSnapshot{state: :ready, repository: "acme/app", template_tag: "sha-new", node_name: "node-a"} =
             snapshot = Repo.get!(DiskSnapshot, save.snapshot_id)

    assert snapshot.agent_environment_id == agent_environment.id
    assert snapshot.setup_sha256 == build.setup_sha256
    refute Repo.get(DiskSnapshot, build.id)
    refute Repo.get(Sandbox, build.id)

    # Sessions boot from it now.
    assert ClaudeCodeSnapshots.find(agent_environment, %{owner: "acme", name: "app"}).id == snapshot.id
  end

  test "a builder another admission of the account kept out is created on a later check", %{
    build: build,
    test_pid: test_pid
  } do
    stub(Sandboxes, :create_sandbox, fn account, attrs, opts ->
      call_original(Sandboxes, :create_sandbox, [account, attrs, opts])
    end)

    expect(Sandboxes, :create_sandbox, fn _account, _attrs, [id: id] when id == build.id ->
      {:error, :sandbox_account_busy}
    end)

    assert {:snooze, 60} = advance(build)
    assert %DiskSnapshot{state: :building} = Repo.get!(DiskSnapshot, build.id)

    stub_node(test_pid)
    assert {:snooze, 30} = advance(build)
    assert [{:create, _create}, {:exec, _start}] = node_calls()
  end

  test "a failed script deletes the builder and keeps the script from building the repository for a while", %{
    agent_environment: agent_environment,
    build: build,
    test_pid: test_pid
  } do
    stub_node(test_pid, "npm ERR! missing script\n")
    assert {:snooze, 30} = advance(build)
    _calls = node_calls()

    finish_command(build, 1)
    assert :ok = advance(build)
    # The output tail is read for the log before the builder goes.
    assert [{:exec, _tail}, {:delete, _delete}] = node_calls()
    assert %DiskSnapshot{state: :failed} = Repo.get!(DiskSnapshot, build.id)

    sha = ClaudeCodeSnapshots.setup_sha256(@setup_script)
    assert {:error, :already_building} = DiskSnapshots.start_build(agent_environment, "acme/app", sha)
    # Another repository, or a fixed script, builds at once.
    assert {:ok, _build} = DiskSnapshots.start_build(agent_environment, "acme/web", sha)
    assert {:ok, _build} = DiskSnapshots.start_build(agent_environment, "acme/app", "fixed")

    Repo.update_all(from(s in DiskSnapshot, where: s.id == ^build.id),
      set: [updated_at: DateTime.add(DateTime.utc_now(:second), -61, :minute)]
    )

    DiskSnapshots.delete_expired()
    assert {:ok, _build} = DiskSnapshots.start_build(agent_environment, "acme/app", sha)
  end

  test "a build whose script changed is dropped with its builder", %{
    agent_environment: agent_environment,
    build: build,
    test_pid: test_pid
  } do
    stub_node(test_pid)
    assert {:snooze, 30} = advance(build)
    _calls = node_calls()

    {:ok, _updated} = Sandboxes.update_agent_environment(agent_environment, %{setup_script: "mise install\n"})
    assert :ok = advance(build)
    assert [{:delete, _delete}] = node_calls()
    refute Repo.get(DiskSnapshot, build.id)
  end

  test "a build stuck past its command's deadline is dropped with its builder", %{account: account, build: build} do
    sandbox_fixture(account: account, id: build.id, node_name: "node-a")

    Repo.update_all(from(s in DiskSnapshot, where: s.id == ^build.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -91, :minute)]
    )

    expect(Nodes, :call, fn "node-a", "delete", %{sandbox_id: id}, _opts when id == build.id -> {:ok, %{}} end)

    DiskSnapshots.delete_expired()
    refute Repo.get(DiskSnapshot, build.id)
    refute Repo.get(Sandbox, build.id)
  end
end
