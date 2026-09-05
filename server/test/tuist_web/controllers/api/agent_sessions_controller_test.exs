defmodule TuistWeb.API.AgentSessionsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes.AgentSession
  alias Tuist.Sandboxes.Anthropic.ControlPlane
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

  describe "create" do
    test "starts a session on the account's environment and records who started it", %{
      conn: conn,
      account: account,
      user: user
    } do
      agent_environment =
        agent_environment_fixture(
          account: account,
          anthropic_environment_id: "env_ctrl",
          anthropic_api_key: "sk-ant-api",
          anthropic_agent_id: "agent_cached"
        )

      reject(&ControlPlane.create_agent/2)

      expect(ControlPlane, :create_session, fn "sk-ant-api", attrs ->
        assert attrs.agent == "agent_cached"
        assert attrs.environment_id == "env_ctrl"
        assert attrs.budget_cents == 1000
        assert attrs.initial_events == [%{type: "user.message", content: [%{type: "text", text: "Fix the build."}]}]
        {:ok, %{"id" => "sesn_ctrl", "status" => "running"}}
      end)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions", %{
          prompt: "Fix the build.",
          title: "Fix",
          repository_url: "https://github.com/tuist/tuist.git",
          repository_ref: "main",
          budget_cents: 1000
        })
        |> json_response(:created)

      assert %{
               "id" => id,
               "anthropic_session_id" => "sesn_ctrl",
               "anthropic_agent_id" => "agent_cached",
               "agent_environment_id" => agent_environment_id,
               "sandbox_id" => nil,
               "title" => "Fix",
               "repository_url" => "https://github.com/tuist/tuist.git",
               "repository_ref" => "main",
               "model" => "claude-sonnet-5",
               "budget_cents" => 1000,
               "status" => "running",
               "stop_reason" => nil
             } = response

      assert agent_environment_id == agent_environment.id
      assert is_binary(response["inserted_at"])
      refute inspect(response) =~ "sk-ant-api"

      assert %AgentSession{created_by_user_id: created_by_user_id} = Repo.get(AgentSession, id)
      assert created_by_user_id == user.id
    end

    test "answers 400 when no environment can run the session", %{conn: conn, account: account} do
      reject(&ControlPlane.create_session/2)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions", %{prompt: "Fix the build."})
        |> json_response(:bad_request)

      assert response["message"] =~ "agent environment"

      agent_environment_fixture(account: account)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions", %{prompt: "Fix the build."})
        |> json_response(:bad_request)

      assert response["message"] =~ "API key"
    end

    test "answers 400 for invalid params", %{conn: conn, account: account} do
      agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api", anthropic_agent_id: "agent_cached")
      reject(&ControlPlane.create_session/2)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions", %{title: "no prompt"})
      |> json_response(:bad_request)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions", %{
          prompt: "Fix the build.",
          repository_url: "git@github.com:tuist/tuist.git"
        })
        |> json_response(:bad_request)

      assert response["message"] =~ "repository_url"
    end

    test "answers 502 when Anthropic rejects the session", %{conn: conn, account: account} do
      agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api", anthropic_agent_id: "agent_cached")

      expect(ControlPlane, :create_session, fn _key, _attrs ->
        {:error, %{status: 400, message: "environment not found"}}
      end)

      response =
        conn
        |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions", %{prompt: "Fix the build."})
        |> json_response(:bad_gateway)

      assert response["message"] =~ "environment not found"
    end
  end

  describe "index and show" do
    test "lists the account's sessions and shows one with its live status", %{conn: conn, account: account} do
      sandbox = sandbox_fixture(account: account, state: :running)
      agent_session = agent_session_fixture(account: account, anthropic_session_id: "sesn_show", sandbox_id: sandbox.id)
      foreign = agent_session_fixture()
      id = agent_session.id

      assert %{"agent_sessions" => [%{"id" => ^id, "status" => "running"}]} =
               conn |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions") |> json_response(:ok)

      expect(ControlPlane, :get_session, fn "sk-ant-api-fixture", "sesn_show" ->
        {:ok,
         %{
           "status" => "idle",
           "usage" => %{"input_tokens" => 7, "output_tokens" => 3, "list_cost" => %{"amount" => "4", "currency" => "USD"}}
         }}
      end)

      expect(ControlPlane, :list_events, fn "sk-ant-api-fixture", "sesn_show", _opts ->
        {:ok, [%{"type" => "session.status_idle", "stop_reason" => %{"type" => "budget_reached"}}]}
      end)

      shown =
        conn
        |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions/#{id}")
        |> json_response(:ok)

      assert %{
               "id" => ^id,
               "status" => "idle",
               "stop_reason" => "budget_reached",
               "sandbox_state" => "running",
               "usage" => %{
                 "input_tokens" => 7,
                 "output_tokens" => 3,
                 "cache_read_input_tokens" => nil,
                 "active_seconds" => nil,
                 "list_cost" => %{"amount" => "4", "currency" => "USD"}
               }
             } = shown

      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions/#{foreign.id}") |> json_response(:not_found)
      conn |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions/not-a-uuid") |> json_response(:not_found)
    end
  end

  describe "messages, events and archive" do
    test "queues a message for the session", %{conn: conn, account: account} do
      agent_session = agent_session_fixture(account: account, anthropic_session_id: "sesn_msg")

      expect(ControlPlane, :send_message, fn "sk-ant-api-fixture", "sesn_msg", "Now run the tests." ->
        {:ok, %{"data" => []}}
      end)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions/#{agent_session.id}/messages", %{
        text: "Now run the tests."
      })
      |> response(:accepted)

      reject(&ControlPlane.send_message/3)

      conn
      |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions/#{agent_session.id}/messages", %{})
      |> json_response(:bad_request)
    end

    test "returns the events after an index", %{conn: conn, account: account} do
      agent_session = agent_session_fixture(account: account, anthropic_session_id: "sesn_evt")

      expect(ControlPlane, :list_events, 2, fn "sk-ant-api-fixture", "sesn_evt", [] ->
        {:ok,
         [
           %{
             "type" => "user.message",
             "processed_at" => "2026-09-05T10:00:00Z",
             "content" => [%{"type" => "text", "text" => "Go"}]
           },
           %{
             "type" => "agent.tool_use",
             "processed_at" => "2026-09-05T10:00:01Z",
             "name" => "bash",
             "input" => %{"command" => "ls"}
           },
           %{
             "type" => "session.status_idle",
             "processed_at" => "2026-09-05T10:00:02Z",
             "stop_reason" => %{"type" => "end_turn"}
           }
         ]}
      end)

      assert %{"events" => events, "next_after" => 2} =
               conn
               |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions/#{agent_session.id}/events")
               |> json_response(:ok)

      assert [
               %{"index" => 0, "type" => "user.message", "text" => "Go", "command" => nil},
               %{"index" => 1, "type" => "agent.tool_use", "tool_name" => "bash", "command" => "ls"},
               %{
                 "index" => 2,
                 "type" => "session.status_idle",
                 "stop_reason" => "end_turn",
                 "at" => "2026-09-05T10:00:02Z"
               }
             ] = events

      assert %{"events" => [%{"index" => 2}], "next_after" => 2} =
               conn
               |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions/#{agent_session.id}/events?after=1")
               |> json_response(:ok)
    end

    test "archives the session", %{conn: conn, account: account} do
      agent_session = agent_session_fixture(account: account, anthropic_session_id: "sesn_arch")
      id = agent_session.id

      expect(ControlPlane, :archive_session, fn "sk-ant-api-fixture", "sesn_arch" -> {:ok, %{"id" => "sesn_arch"}} end)

      assert %{"id" => ^id, "status" => "archived"} =
               conn
               |> post(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions/#{id}/archive")
               |> json_response(:ok)
    end
  end

  describe "authorization" do
    test "forbids a user who is not an admin of the account", %{conn: conn, account: account} do
      other_user = AccountsFixtures.user_fixture()

      response =
        conn
        |> Authentication.put_current_user(other_user)
        |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions")
        |> json_response(:forbidden)

      assert response["message"] =~ "not authorized"
    end

    test "requires authentication", %{account: account} do
      build_conn()
      |> get(~p"/api/accounts/#{account.name}/sandboxes/agent-sessions")
      |> json_response(:unauthorized)
    end
  end
end
