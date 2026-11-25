defmodule Tuist.Sandboxes.ClaudeCodeSnapshotsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.ProjectsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.GitHub
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.ClaudeCodeSnapshots
  alias Tuist.Sandboxes.CommandCredentials
  alias Tuist.Sandboxes.Commands
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
    refute Map.has_key?(start.env, "TUIST_OIDC_TOKEN")
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

  test "a macOS build runs the script as the guest's user and saves the builder's disks on its host", %{
    account: account,
    test_pid: test_pid
  } do
    agent_environment =
      agent_environment_fixture(
        account: account,
        kind: :claude_code,
        anthropic_environment_id: "ccpool_01macos",
        platform: :darwin,
        template: "default",
        vcpus: 8,
        memory_mb: 8192,
        setup_script: @setup_script
      )

    {:ok, build} =
      DiskSnapshots.start_build(agent_environment, "acme/app", ClaudeCodeSnapshots.setup_sha256(@setup_script))

    stub_node(test_pid)

    assert {:snooze, 30} = advance(build)
    assert [{:create, create}, {:hold_residency, _hold}, {:exec, start}] = node_calls()
    assert create.sandbox_id == build.id
    assert %Sandbox{platform: :darwin} = Repo.get!(Sandbox, build.id)

    # macOS runs guest commands as `runner` already: no runuser, which the
    # guest lacks.
    command = start.env["TUIST_COMMAND"]
    assert command =~ "git clone --quiet"
    refute command =~ "runuser"
    assert command =~ "'/Users/runner/work/claude-code/acme/app' 'https://github.com/acme/app'"

    finish_command(build, 0)
    assert :ok = advance(build)
    calls = node_calls()
    assert {:pause, pause} = List.keyfind(calls, :pause, 0)
    assert {:save_disks, save} = List.keyfind(calls, :save_disks, 0)
    assert List.keymember?(calls, :delete, 0)
    assert pause.sync_disks
    assert save.sandbox_id == build.id

    assert %DiskSnapshot{state: :ready, platform: :darwin, repository: "acme/app"} =
             snapshot = Repo.get!(DiskSnapshot, save.snapshot_id)

    assert ClaudeCodeSnapshots.find(agent_environment, %{owner: "acme", name: "app"}).id == snapshot.id
  end

  test "a Mac a Linux session creates for a connected repository has its snapshot built where sync puts the worktree",
       %{account: account, agent_environment: agent_environment, test_pid: test_pid} do
    {:ok, agent_environment} =
      Sandboxes.update_agent_environment(agent_environment, %{macos_setup_script: "mise install && tuist generate\n"})

    project_fixture(account: account, vcs_connection: [repository_full_handle: "acme/app"])

    stub(Nodes, :connected_nodes, fn ->
      [%{name: "node-a", disk: %{}, templates: [%{name: "macos", ready: true, tag: "sha-new", rootfs_bytes: 1}]}]
    end)

    stub_node(test_pid)

    # The environment's own Linux snapshot of the repository, which a Mac's
    # must leave alone.
    {:ok, linux_snapshot} =
      %DiskSnapshot{state: :ready}
      |> DiskSnapshot.create_changeset(%{
        account_id: account.id,
        agent_environment_id: agent_environment.id,
        repository: "acme/app",
        setup_sha256: ClaudeCodeSnapshots.setup_sha256(@setup_script),
        node_name: "node-a",
        template: "default",
        workspace_gb: agent_environment.workspace_gb,
        last_used_at: DateTime.utc_now(:second)
      })
      |> Repo.insert()

    # Named in another case, the repository takes its connected name.
    assert {:ok, %{snapshot: nil, repository: "acme/app", template: "macos"} = source} =
             ClaudeCodeSnapshots.mac_source(account, "ACME/app", %{platform: "darwin"})

    assert :ok = ClaudeCodeSnapshots.request_mac_build(source)

    assert %DiskSnapshot{state: :building, platform: :darwin, template: "macos"} =
             build =
             Repo.one!(from(d in DiskSnapshot, where: d.state == :building and d.platform == :darwin))

    assert {:snooze, 30} = advance(build)
    assert [{:create, create}, {:hold_residency, _hold}, {:exec, start}] = node_calls()
    assert create.template == "macos"
    assert %Sandbox{platform: :darwin, vcpus: 8} = Repo.get!(Sandbox, build.id)

    # Cloned to `$HOME/work/<name>`, sync's default path, with the macOS
    # script, and recorded as sync records what it sent.
    command = start.env["TUIST_COMMAND"]
    assert command =~ "'/Users/runner/work/app' 'https://github.com/acme/app'"
    assert command =~ "'mise install && tuist generate\n'"
    assert command =~ ~S|state="$HOME/.tuist-sync/|
    assert command =~ "git rev-parse HEAD > \"$state/commit\""

    # Its script signs in with read access to the account's cache while the
    # build runs, and the build removes the session before saving.
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _account -> true end)
    assert {:ok, %{sandbox_command: claims}} = CommandCredentials.claims(start.env["TUIST_OIDC_TOKEN"])
    assert {:ok, %{id: account_id}, grant} = CommandCredentials.account_grant(claims)
    assert account_id == account.id
    assert grant == %{"all_projects" => true, "scopes" => ["account:cache:read", "project:cache:read"]}
    assert command =~ ~S|rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/tuist/credentials"|
    # It keeps the compilation cache and flushes it to disk once its writers
    # have exited.
    assert command =~ ~r/pgrep -x XCBBuildService.*find "\$cache" -type f -exec perl .*fcntl\(\$f, 51, 0\)/s
    refute command =~ ~S|rm -rf "$cache"|
    assert command =~ "unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_TERMINAL_PROMPT\n"

    finish_command(build, 0)
    assert :ok = advance(build)
    assert {:error, :sandbox_command_not_running} = CommandCredentials.account_grant(claims)

    assert %DiskSnapshot{state: :ready, platform: :darwin, template: "macos", template_tag: "sha-new"} =
             snapshot =
             Repo.one!(from(d in DiskSnapshot, where: d.state == :ready and d.platform == :darwin))

    assert Repo.get(DiskSnapshot, linux_snapshot.id)

    # The next Mac of that Xcode boots from it; another Xcode's has none yet.
    assert {:ok, %{snapshot: %DiskSnapshot{id: id}}} =
             ClaudeCodeSnapshots.mac_source(account, "acme/app", %{platform: "darwin"})

    assert id == snapshot.id

    assert {:ok, %{snapshot: nil, template: "macos-xcode-1-2"}} =
             ClaudeCodeSnapshots.mac_source(account, "acme/app", %{platform: "darwin", template: "macos-xcode-1-2"})

    # A Mac that boots from it builds nothing new while it is recent, and has
    # it built again once it is older than six hours.
    building = fn ->
      Repo.aggregate(from(d in DiskSnapshot, where: d.state == :building and d.platform == :darwin), :count)
    end

    assert {:ok, source} = ClaudeCodeSnapshots.mac_source(account, "acme/app", %{platform: "darwin"})
    assert :ok = ClaudeCodeSnapshots.request_mac_build(source)
    assert building.() == 0

    snapshot
    |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(:second), -7, :hour))
    |> Repo.update!()

    assert {:ok, %{snapshot: %DiskSnapshot{}} = source} =
             ClaudeCodeSnapshots.mac_source(account, "acme/app", %{platform: "darwin"})

    assert :ok = ClaudeCodeSnapshots.request_mac_build(source)
    assert building.() == 1
  end

  test "only a Mac for a repository connected to the account's projects has a snapshot source", %{
    account: account,
    agent_environment: agent_environment
  } do
    other_account = account_fixture()
    project_fixture(account: other_account, vcs_connection: [repository_full_handle: "acme/secret"])
    project_fixture(account: account, vcs_connection: [repository_full_handle: "acme/app"])

    # The environment has no macOS setup script yet.
    assert {:ok, nil} = ClaudeCodeSnapshots.mac_source(account, "acme/app", %{platform: "darwin"})

    {:ok, _agent_environment} =
      Sandboxes.update_agent_environment(agent_environment, %{macos_setup_script: "mise install\n"})

    assert {:ok, %{repository: "acme/app"}} = ClaudeCodeSnapshots.mac_source(account, "acme/app", %{platform: "darwin"})
    assert {:ok, nil} = ClaudeCodeSnapshots.mac_source(account, "acme/secret", %{platform: "darwin"})
    assert {:ok, nil} = ClaudeCodeSnapshots.mac_source(account, "acme/app", %{})
    assert {:ok, nil} = ClaudeCodeSnapshots.mac_source(account, nil, %{platform: "darwin"})
    assert {:error, :invalid_parameters} = ClaudeCodeSnapshots.mac_source(account, "acme", %{platform: "darwin"})
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

  test "a builder whose host CI took before its first command is replaced on a later check", %{
    build: build,
    test_pid: test_pid
  } do
    stub_node(test_pid)
    stub(Commands, :start, fn sandbox, params -> call_original(Commands, :start, [sandbox, params]) end)
    expect(Commands, :start, fn _sandbox, %{id: id} when id == build.id -> {:error, {:host_busy, :ci}} end)

    assert {:snooze, 60} = advance(build)
    assert %DiskSnapshot{state: :building} = Repo.get!(DiskSnapshot, build.id)
    assert [{:create, _create}, {:delete, _delete}] = node_calls()

    assert {:snooze, 30} = advance(build)
    assert [{:create, _create}, {:exec, _start}] = node_calls()
  end

  test "a finished build saves within its builder's disk reservation and waits while the node's filesystem is full", %{
    build: build,
    test_pid: test_pid
  } do
    stub_node(test_pid)
    assert {:snooze, 30} = advance(build)
    _calls = node_calls()
    finish_command(build, 0)

    template = %{name: "default", ready: true, tag: "sha-new", rootfs_bytes: 1}
    node = %{name: "node-a", templates: [template]}
    builder = Repo.get!(Sandbox, build.id)
    connect = fn disk -> stub(Nodes, :connected_nodes, fn -> [Map.put(node, :disk, disk)] end) end

    # No room on the filesystem: the finished builder stays, paused.
    connect.(%{available_bytes: 0})
    assert {:snooze, 60} = advance(build)
    assert [{:pause, _pause}] = node_calls()
    assert %DiskSnapshot{state: :building} = Repo.get!(DiskSnapshot, build.id)
    assert %Sandbox{state: :paused} = Repo.get!(Sandbox, build.id)

    # A budget that holds only the builder holds its snapshot, which
    # replaces it.
    connect.(%{budget_bytes: Capacity.disk_ceiling_bytes(builder, node)})
    assert :ok = advance(build)
    assert [{:save_disks, save}, {:delete, _delete}] = node_calls()
    assert %DiskSnapshot{state: :ready, repository: "acme/app"} = Repo.get!(DiskSnapshot, save.snapshot_id)
    refute Repo.get(Sandbox, build.id)
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
