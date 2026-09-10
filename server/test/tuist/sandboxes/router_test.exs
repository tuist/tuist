defmodule Tuist.Sandboxes.RouterTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import ExUnit.CaptureLog
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Environment
  alias Tuist.GitHub
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentSession
  alias Tuist.Sandboxes.Anthropic.Client
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Router
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.VCS

  setup do
    account = account_fixture()

    agent_environment =
      agent_environment_fixture(
        account: account,
        anthropic_environment_id: "env_router",
        environment_key: "sk-ant-router",
        max_idle_seconds: 45
      )

    %{account: account, agent_environment: agent_environment}
  end

  defp work_item(session_id, work_id \\ "work_1") do
    %{
      "id" => work_id,
      "type" => "work",
      "data" => %{"id" => session_id, "type" => "session"},
      "secret" => "work-secret",
      "state" => "starting"
    }
  end

  test "creates a sandbox for a new session and starts the worker with the session credentials", %{
    account: account,
    agent_environment: agent_environment
  } do
    stub(Environment, :anthropic_api_url_override, fn -> nil end)
    expect(Nodes, :node_with_capacity, fn %{template: "default"} -> {:ok, "node-a"} end)
    expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{"boot_ms" => 100}} end)

    expect(Nodes, :call, fn "node-a", "start_worker", %{sandbox_id: sandbox_id, env: env}, _opts ->
      assert %Sandbox{residency_work_id: "work_1", residency_epoch: 1, state: :running} = Repo.get(Sandbox, sandbox_id)

      assert env == %{
               "ANTHROPIC_SESSION_ID" => "session_1",
               "ANTHROPIC_WORK_ID" => "work_1",
               "ANTHROPIC_ENVIRONMENT_ID" => "env_router",
               "ANTHROPIC_ENVIRONMENT_KEY" => "sk-ant-router",
               "ANTHROPIC_WORK_SECRET" => "work-secret",
               "SBX_MAX_IDLE" => "45s"
             }

      {:ok, %{"pid" => 42}}
    end)

    reject(&Client.stop/4)

    assert :ok = Router.dispatch(agent_environment, work_item("session_1"))

    assert %Sandbox{
             account_id: account_id,
             anthropic_session_id: "session_1",
             residency_work_id: "work_1",
             node_name: "node-a"
           } = Sandboxes.get_sandbox_for_session(agent_environment.id, "session_1")

    assert account_id == account.id
  end

  test "adds ANTHROPIC_BASE_URL when the API URL is overridden", %{agent_environment: agent_environment} do
    stub(Environment, :anthropic_api_url_override, fn -> "http://anthropic.test" end)
    expect(Nodes, :node_with_capacity, fn _ -> {:ok, "node-a"} end)
    expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

    expect(Nodes, :call, fn "node-a", "start_worker", %{env: env}, _opts ->
      assert env["ANTHROPIC_BASE_URL"] == "http://anthropic.test"
      {:ok, %{}}
    end)

    assert :ok = Router.dispatch(agent_environment, work_item("session_2"))
  end

  test "resumes the session's paused sandbox instead of creating one", %{
    account: account,
    agent_environment: agent_environment
  } do
    sandbox =
      sandbox_fixture(
        account: account,
        agent_environment_id: agent_environment.id,
        anthropic_session_id: "session_3",
        state: :paused,
        node_name: "node-b",
        residency_epoch: 6
      )

    sandbox_id = sandbox.id
    reject(&Nodes.node_with_capacity/1)
    expect(Nodes, :call, fn "node-b", "resume", %{sandbox_id: ^sandbox_id}, _opts -> {:ok, %{"restore_ms" => 50}} end)
    expect(Nodes, :call, fn "node-b", "start_worker", %{sandbox_id: ^sandbox_id}, _opts -> {:ok, %{}} end)

    assert :ok = Router.dispatch(agent_environment, work_item("session_3", "work_7"))

    assert %Sandbox{state: :running, residency_work_id: "work_7", residency_epoch: 7} = Repo.reload!(sandbox)
  end

  test "replaces an errored sandbox for the session", %{account: account, agent_environment: agent_environment} do
    dead =
      sandbox_fixture(
        account: account,
        agent_environment_id: agent_environment.id,
        anthropic_session_id: "session_4",
        state: :error,
        node_name: "node-b"
      )

    dead_id = dead.id
    expect(Nodes, :call, fn "node-b", "delete", %{sandbox_id: ^dead_id}, _opts -> {:ok, %{}} end)
    expect(Nodes, :node_with_capacity, fn _ -> {:ok, "node-a"} end)
    expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)
    expect(Nodes, :call, fn "node-a", "start_worker", _args, _opts -> {:ok, %{}} end)

    assert :ok = Router.dispatch(agent_environment, work_item("session_4"))

    assert Repo.get(Sandbox, dead_id) == nil

    assert %Sandbox{state: :running, node_name: "node-a"} =
             Sandboxes.get_sandbox_for_session(agent_environment.id, "session_4")
  end

  test "releases the work item when no node can host the sandbox", %{agent_environment: agent_environment} do
    expect(Nodes, :node_with_capacity, fn _ -> {:error, :no_node} end)
    expect(Client, :stop, fn "env_router", "sk-ant-router", "work_1", true -> {:ok, %{"state" => "stopped"}} end)

    assert {:error, :no_node} = Router.dispatch(agent_environment, work_item("session_5"))
    assert %Sandbox{state: :error} = Sandboxes.get_sandbox_for_session(agent_environment.id, "session_5")
  end

  test "ends the residency and releases the work item when the worker fails to start", %{
    account: account,
    agent_environment: agent_environment
  } do
    sandbox =
      sandbox_fixture(
        account: account,
        agent_environment_id: agent_environment.id,
        anthropic_session_id: "session_6",
        state: :running,
        node_name: "node-b",
        residency_epoch: 0
      )

    expect(Nodes, :call, fn "node-b", "start_worker", _args, _opts -> {:error, "vsock connect refused"} end)
    expect(Client, :stop, fn "env_router", "sk-ant-router", "work_1", true -> {:ok, %{}} end)

    assert {:error, "vsock connect refused"} = Router.dispatch(agent_environment, work_item("session_6"))
    assert %Sandbox{residency_work_id: nil, residency_epoch: 2} = Repo.reload!(sandbox)
  end

  test "releases a work item without a session", %{agent_environment: agent_environment} do
    expect(Client, :stop, fn "env_router", "sk-ant-router", "work_x", true -> {:ok, %{}} end)
    assert {:error, :malformed_work_item} = Router.dispatch(agent_environment, %{"id" => "work_x", "data" => %{}})
  end

  describe "repository staging" do
    @git "/usr/bin/git"

    setup do
      stub(Environment, :anthropic_api_url_override, fn -> nil end)
      :ok
    end

    test "clones the agent session's repository into the new sandbox before the worker starts and binds the sandbox",
         %{account: account, agent_environment: agent_environment} do
      agent_session =
        agent_session_fixture(
          account: account,
          agent_environment: agent_environment,
          anthropic_session_id: "session_repo",
          repository_url: "https://github.com/tuist/tuist.git",
          repository_ref: "main"
        )

      expect(VCS, :get_github_app_installation_for_account, fn _account_id -> {:error, :not_found} end)
      expect(Nodes, :node_with_capacity, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

      expect(Nodes, :call, fn "node-a", "exec", args, opts ->
        assert args.cmd == [
                 @git,
                 "clone",
                 "--filter=blob:none",
                 "--branch",
                 "main",
                 "https://github.com/tuist/tuist.git",
                 "/workspace/tuist"
               ]

        assert args.timeout_ms == 90_000
        assert args.env == %{"GIT_TERMINAL_PROMPT" => "0"}
        assert opts[:timeout] == 100_000
        {:ok, %{"exit_code" => 0}}
      end)

      expect(Nodes, :call, fn "node-a", "start_worker", _args, _opts -> {:ok, %{}} end)

      assert :ok = Router.dispatch(agent_environment, work_item("session_repo"))

      %Sandbox{id: sandbox_id} = Sandboxes.get_sandbox_for_session(agent_environment.id, "session_repo")
      assert %AgentSession{sandbox_id: ^sandbox_id} = Repo.reload!(agent_session)
    end

    test "clones private github.com repositories with the installation token and keeps it out of the logs", %{
      account: account,
      agent_environment: agent_environment
    } do
      agent_session_fixture(
        account: account,
        agent_environment: agent_environment,
        anthropic_session_id: "session_private",
        repository_url: "https://github.com/tuist/private.git"
      )

      account_id = account.id
      installation = %{installation_id: "123", account_id: account_id}
      expect(VCS, :get_github_app_installation_for_account, fn ^account_id -> {:ok, installation} end)

      expect(GitHub.App, :get_installation_token, fn ^installation, [] ->
        {:ok, %{token: "ghs_secret_token", expires_at: DateTime.utc_now()}}
      end)

      expect(Nodes, :node_with_capacity, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

      expect(Nodes, :call, fn "node-a", "exec", args, opts ->
        assert args.cmd == [
                 @git,
                 "clone",
                 "--filter=blob:none",
                 "https://x-access-token:ghs_secret_token@github.com/tuist/private.git",
                 "/workspace/private"
               ]

        opts[:on_stream].(
          {:stderr, "fatal: could not read from 'https://x-access-token:ghs_secret_token@github.com/tuist/private.git'\n"}
        )

        {:ok, %{"exit_code" => 128}}
      end)

      expect(Nodes, :call, fn "node-a", "start_worker", _args, _opts -> {:ok, %{}} end)

      log = capture_log(fn -> assert :ok = Router.dispatch(agent_environment, work_item("session_private")) end)

      assert log =~ "repository clone failed"
      refute log =~ "ghs_secret_token"
    end

    test "checks a commit sha out after cloning", %{account: account, agent_environment: agent_environment} do
      sha = String.duplicate("a", 40)

      agent_session_fixture(
        account: account,
        agent_environment: agent_environment,
        anthropic_session_id: "session_sha",
        repository_url: "https://github.com/tuist/tuist",
        repository_ref: sha
      )

      expect(VCS, :get_github_app_installation_for_account, fn _account_id -> {:error, :not_found} end)
      expect(Nodes, :node_with_capacity, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

      expect(Nodes, :call, fn "node-a", "exec", args, _opts ->
        assert args.cmd == [@git, "clone", "--filter=blob:none", "https://github.com/tuist/tuist", "/workspace/tuist"]
        {:ok, %{"exit_code" => 0}}
      end)

      expect(Nodes, :call, fn "node-a", "exec", args, _opts ->
        assert args.cmd == [@git, "-C", "/workspace/tuist", "checkout", sha]
        assert args.timeout_ms == 60_000
        {:ok, %{"exit_code" => 0}}
      end)

      expect(Nodes, :call, fn "node-a", "start_worker", _args, _opts -> {:ok, %{}} end)

      assert :ok = Router.dispatch(agent_environment, work_item("session_sha"))
    end

    test "starts the worker even when the clone times out", %{account: account, agent_environment: agent_environment} do
      agent_session_fixture(
        account: account,
        agent_environment: agent_environment,
        anthropic_session_id: "session_timeout",
        repository_url: "https://gitlab.com/acme/app.git"
      )

      reject(&VCS.get_github_app_installation_for_account/1)
      expect(Nodes, :node_with_capacity, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, fn "node-a", "exec", _args, _opts -> {:error, :timeout} end)

      expect(Nodes, :call, fn "node-a", "start_worker", %{sandbox_id: sandbox_id}, _opts ->
        assert %Sandbox{residency_work_id: "work_1"} = Repo.get(Sandbox, sandbox_id)
        {:ok, %{}}
      end)

      log = capture_log(fn -> assert :ok = Router.dispatch(agent_environment, work_item("session_timeout")) end)
      assert log =~ "repository clone failed"
    end

    test "falls back to the work item's metadata when no agent session row exists", %{
      agent_environment: agent_environment
    } do
      item =
        put_in(work_item("session_meta"), ["data", "metadata"], %{
          "repository_url" => "https://gitlab.com/acme/app.git",
          "repository_ref" => ""
        })

      reject(&VCS.get_github_app_installation_for_account/1)
      expect(Nodes, :node_with_capacity, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)

      expect(Nodes, :call, fn "node-a", "exec", args, _opts ->
        assert args.cmd == [@git, "clone", "--filter=blob:none", "https://gitlab.com/acme/app.git", "/workspace/app"]
        {:ok, %{"exit_code" => 0}}
      end)

      expect(Nodes, :call, fn "node-a", "start_worker", _args, _opts -> {:ok, %{}} end)

      assert :ok = Router.dispatch(agent_environment, item)
    end

    test "binds the sandbox without touching git when the session has no repository", %{
      account: account,
      agent_environment: agent_environment
    } do
      agent_session =
        agent_session_fixture(
          account: account,
          agent_environment: agent_environment,
          anthropic_session_id: "session_bare"
        )

      expect(Nodes, :node_with_capacity, fn _ -> {:ok, "node-a"} end)
      expect(Nodes, :call, fn "node-a", "create", _args, _opts -> {:ok, %{}} end)
      expect(Nodes, :call, fn "node-a", "start_worker", _args, _opts -> {:ok, %{}} end)

      assert :ok = Router.dispatch(agent_environment, work_item("session_bare"))

      %Sandbox{id: sandbox_id} = Sandboxes.get_sandbox_for_session(agent_environment.id, "session_bare")
      assert %AgentSession{sandbox_id: ^sandbox_id} = Repo.reload!(agent_session)
    end
  end
end
