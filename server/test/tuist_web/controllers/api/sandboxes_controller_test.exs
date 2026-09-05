defmodule TuistWeb.API.SandboxesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Repo
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])

    conn =
      conn
      |> Authentication.put_current_user(user)
      |> put_req_header("content-type", "application/json")

    %{conn: conn, user: user, account: user.account}
  end

  describe "agent environments" do
    test "creates, lists and deletes an agent environment without ever returning the key", %{
      conn: conn,
      account: account
    } do
      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          anthropic_environment_id: "env_abc",
          environment_key: "sk-ant-secret",
          name: "prod",
          vcpus: 4,
          memory_mb: 8192
        })
        |> json_response(:created)

      assert %{"anthropic_environment_id" => "env_abc", "name" => "prod", "vcpus" => 4, "memory_mb" => 8192} = response
      refute Map.has_key?(response, "environment_key")
      refute inspect(response) =~ "sk-ant-secret"

      listed =
        conn
        |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-environments")
        |> json_response(:ok)

      assert [%{"id" => id, "anthropic_environment_id" => "env_abc", "enabled" => true}] = listed["agent_environments"]
      refute inspect(listed) =~ "sk-ant-secret"

      conn
      |> delete(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{id}")
      |> response(:no_content)

      assert %{"agent_environments" => []} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-environments") |> json_response(:ok)
    end

    test "rejects invalid params", %{conn: conn, account: account} do
      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          anthropic_environment_id: "env_abc",
          environment_key: "sk-ant-secret",
          vcpus: 0
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "minimum"

      agent_environment_fixture(anthropic_environment_id: "env_taken")

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          anthropic_environment_id: "env_taken",
          environment_key: "sk-ant-secret"
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "anthropic_environment_id has already been taken"
    end

    test "answers 404 for another account's agent environment", %{conn: conn, account: account} do
      other = agent_environment_fixture()

      conn
      |> delete(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{other.id}")
      |> json_response(:not_found)

      conn
      |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{other.id}", %{agent_model: "claude-opus-5"})
      |> json_response(:not_found)
    end

    test "stores the agent settings, reports has_api_key and drops the cached agent when the model changes", %{
      conn: conn,
      account: account
    } do
      created =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-environments", %{
          anthropic_environment_id: "env_agent",
          environment_key: "sk-ant-secret",
          anthropic_api_key: "sk-ant-api",
          agent_model: "claude-opus-5",
          agent_system_prompt: "Be brief."
        })
        |> json_response(:created)

      assert %{
               "has_api_key" => true,
               "agent_model" => "claude-opus-5",
               "agent_system_prompt" => "Be brief.",
               "anthropic_agent_id" => nil
             } = created

      refute Map.has_key?(created, "anthropic_api_key")
      refute inspect(created) =~ "sk-ant-api"

      agent_environment = agent_environment_fixture(account: account, anthropic_agent_id: "agent_cached")

      listed =
        conn
        |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-environments")
        |> json_response(:ok)

      assert %{"has_api_key" => false, "anthropic_agent_id" => "agent_cached", "agent_model" => "claude-sonnet-5"} =
               Enum.find(listed["agent_environments"], &(&1["id"] == agent_environment.id))

      updated =
        conn
        |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{agent_environment.id}", %{
          anthropic_api_key: "sk-ant-api-2"
        })
        |> json_response(:ok)

      assert %{"has_api_key" => true, "anthropic_agent_id" => "agent_cached", "agent_model" => "claude-sonnet-5"} =
               updated

      refute inspect(updated) =~ "sk-ant-api-2"

      assert %{"anthropic_agent_id" => nil, "agent_model" => "claude-opus-5", "has_api_key" => true} =
               conn
               |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{agent_environment.id}", %{
                 agent_model: "claude-opus-5"
               })
               |> json_response(:ok)

      response =
        conn
        |> patch(~p"/api/accounts/#{account.name}/sandboxes/agent-environments/#{agent_environment.id}", %{
          agent_model: ""
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "minLength"
    end
  end

  describe "authorization" do
    test "forbids a user who is not an admin of the account", %{conn: conn, account: account} do
      other_user = AccountsFixtures.user_fixture()

      response =
        conn
        |> Authentication.put_current_user(other_user)
        |> get(~p"/api/accounts/#{account.name}/sandboxes")
        |> json_response(:forbidden)

      assert response["message"] =~ "not authorized"
    end

    test "forbids an account token", %{account: account} do
      build_conn()
      |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:read"]})
      |> get(~p"/api/accounts/#{account.name}/sandboxes")
      |> json_response(:forbidden)
    end

    test "requires authentication", %{account: account} do
      build_conn()
      |> get(~p"/api/accounts/#{account.name}/sandboxes")
      |> json_response(:unauthorized)
    end
  end

  describe "sandboxes" do
    test "creates, inspects, runs commands in, pauses, resumes and deletes a sandbox", %{conn: conn, account: account} do
      stub(Nodes, :node_with_capacity, fn %{template: "default"} -> {:ok, "node-a"} end)

      expect(Nodes, :call, fn "node-a", "create", %{vcpus: 4}, _opts -> {:ok, %{"template_tag" => "sha-1"}} end)

      created =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes", %{vcpus: 4})
        |> json_response(:created)

      assert %{"id" => id, "state" => "running", "node_name" => "node-a", "vcpus" => 4, "template_tag" => "sha-1"} =
               created

      assert created["hostname"] == "sbx-" <> String.slice(id, 0, 8)

      assert %{"sandboxes" => [%{"id" => ^id}]} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes") |> json_response(:ok)

      assert %{"id" => ^id, "state" => "running"} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{id}") |> json_response(:ok)

      expect(Nodes, :call, fn "node-a", "exec", %{cmd: ["/bin/bash", "-lc", "echo hi"], timeout_ms: 2_000}, opts ->
        opts[:on_stream].({:stdout, "hi\n"})
        {:ok, %{"exit_code" => 0}}
      end)

      assert %{"exit_code" => 0, "stdout" => "hi\n", "stderr" => ""} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/#{id}/exec", %{command: "echo hi", timeout_ms: 2_000})
               |> json_response(:ok)

      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:ok, %{}} end)

      assert %{"state" => "paused", "paused_at" => paused_at} =
               conn |> post(~p"/api/accounts/#{account.name}/sandboxes/#{id}/pause") |> json_response(:ok)

      assert is_binary(paused_at)

      expect(Nodes, :call, fn "node-a", "resume", _args, _opts -> {:ok, %{}} end)

      assert %{"state" => "running", "paused_at" => nil} =
               conn |> post(~p"/api/accounts/#{account.name}/sandboxes/#{id}/resume") |> json_response(:ok)

      expect(Nodes, :call, fn "node-a", "delete", _args, _opts -> {:ok, %{}} end)
      conn |> delete(~p"/api/accounts/#{account.name}/sandboxes/#{id}") |> response(:no_content)
      assert Repo.get(Sandbox, id) == nil
    end

    test "answers 503 when no node can host the sandbox", %{conn: conn, account: account} do
      stub(Nodes, :node_with_capacity, fn _ -> {:error, :no_node} end)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes", %{})
        |> json_response(:service_unavailable)

      assert response["message"] =~ "No sandbox node"
    end

    test "answers 409 for an operation the sandbox state does not allow", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :paused)
      reject(&Nodes.call/4)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/pause")
        |> json_response(:conflict)

      assert response["message"] =~ "paused"
    end

    test "answers 502 when the node rejects the operation", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      expect(Nodes, :call, fn "node-a", "pause", _args, _opts -> {:error, "worker running"} end)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/pause")
        |> json_response(:bad_gateway)

      assert response["message"] =~ "worker running"
    end

    test "answers 404 for unknown or foreign sandboxes", %{conn: conn, account: account} do
      foreign = sandbox_fixture()

      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/#{foreign.id}") |> json_response(:not_found)
      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/not-a-uuid") |> json_response(:not_found)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{Ecto.UUID.generate()}/exec", %{command: "ls"})
      |> json_response(:not_found)
    end

    test "validates the exec body", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running, node_name: "node-a")
      reject(&Nodes.call/4)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/#{sandbox.id}/exec", %{})
      |> json_response(:bad_request)
    end
  end
end
