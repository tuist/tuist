defmodule Tuist.Sandboxes.RouterTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Anthropic.Client
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Router
  alias Tuist.Sandboxes.Sandbox

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
end
