defmodule Tuist.Sandboxes.AgentSessionsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.AgentSession
  alias Tuist.Sandboxes.AgentSessions
  alias Tuist.Sandboxes.Anthropic.ControlPlane

  describe "start_agent_session/3" do
    test "creates and caches the agent, opens the session with the prompt and records it" do
      account = account_fixture()
      user = user_fixture()

      agent_environment =
        agent_environment_fixture(
          account: account,
          anthropic_environment_id: "env_start",
          anthropic_api_key: "sk-ant-api"
        )

      default_prompt = AgentSessions.default_system_prompt()
      test_pid = self()

      expect(ControlPlane, :create_agent, fn "sk-ant-api", attrs ->
        assert attrs == %{name: "tuist-" <> account.name, model: "claude-sonnet-5", system: default_prompt}
        {:ok, %{"id" => "agent_new", "version" => 1}}
      end)

      expect(ControlPlane, :create_session, fn "sk-ant-api", attrs ->
        assert attrs.agent == "agent_new"
        assert attrs.environment_id == "env_start"
        assert attrs.title == "Fix the build"
        assert attrs.budget_cents == 500

        assert attrs.initial_events == [
                 %{
                   type: "user.message",
                   content: [
                     %{
                       type: "text",
                       text: "The repository https://github.com/tuist/tuist.git is cloned at /workspace/tuist.

Fix the build."
                     }
                   ]
                 }
               ]

        assert %{
                 "tuist_account" => handle,
                 "tuist_agent_session_id" => id,
                 "repository_url" => "https://github.com/tuist/tuist.git",
                 "repository_ref" => "main"
               } = attrs.metadata

        assert handle == account.name
        assert {:ok, _uuid} = Ecto.UUID.cast(id)
        send(test_pid, {:session_row_id, id})
        {:ok, %{"id" => "sesn_new", "status" => "running"}}
      end)

      assert {:ok, %AgentSession{} = agent_session} =
               Sandboxes.start_agent_session(
                 account,
                 %{
                   prompt: "Fix the build.",
                   title: "Fix the build",
                   repository_url: "https://github.com/tuist/tuist.git",
                   repository_ref: "main",
                   budget_cents: 500
                 },
                 created_by_user_id: user.id
               )

      assert_received {:session_row_id, row_id}
      assert agent_session.id == row_id
      assert agent_session.anthropic_session_id == "sesn_new"
      assert agent_session.anthropic_agent_id == "agent_new"
      assert agent_session.agent_environment_id == agent_environment.id
      assert agent_session.account_id == account.id
      assert agent_session.model == "claude-sonnet-5"
      assert agent_session.budget_cents == 500
      assert agent_session.last_status == "running"
      assert agent_session.created_by_user_id == user.id
      assert %AgentEnvironment{anthropic_agent_id: "agent_new"} = Repo.reload!(agent_environment)
      assert [%AgentSession{id: ^row_id}] = Sandboxes.list_agent_sessions(account)
    end

    test "reuses the cached agent when the model matches" do
      account = account_fixture()
      agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api", anthropic_agent_id: "agent_cached")

      reject(&ControlPlane.create_agent/2)

      expect(ControlPlane, :create_session, fn "sk-ant-api", %{agent: "agent_cached", metadata: metadata} ->
        assert metadata["repository_url"] == ""
        assert metadata["repository_ref"] == ""
        {:ok, %{"id" => "sesn_cached", "status" => "running"}}
      end)

      assert {:ok, %AgentSession{anthropic_agent_id: "agent_cached", model: "claude-sonnet-5"}} =
               Sandboxes.start_agent_session(account, %{prompt: "Hello"})
    end

    test "creates a one-off agent for a model override without caching it" do
      account = account_fixture()

      agent_environment =
        agent_environment_fixture(
          account: account,
          anthropic_api_key: "sk-ant-api",
          anthropic_agent_id: "agent_cached",
          agent_system_prompt: "Be terse."
        )

      expect(ControlPlane, :create_agent, fn "sk-ant-api", %{model: "claude-opus-5", system: "Be terse."} ->
        {:ok, %{"id" => "agent_opus"}}
      end)

      expect(ControlPlane, :create_session, fn "sk-ant-api", %{agent: "agent_opus"} ->
        {:ok, %{"id" => "sesn_opus", "status" => "running"}}
      end)

      assert {:ok, %AgentSession{anthropic_agent_id: "agent_opus", model: "claude-opus-5"}} =
               Sandboxes.start_agent_session(account, %{prompt: "Hello", model: "claude-opus-5"})

      assert %AgentEnvironment{anthropic_agent_id: "agent_cached"} = Repo.reload!(agent_environment)
    end

    test "runs an explicitly given agent" do
      account = account_fixture()
      agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api", anthropic_agent_id: "agent_cached")

      reject(&ControlPlane.create_agent/2)

      expect(ControlPlane, :create_session, fn "sk-ant-api", %{agent: "agent_custom"} ->
        {:ok, %{"id" => "sesn_custom", "status" => "running"}}
      end)

      assert {:ok, %AgentSession{anthropic_agent_id: "agent_custom"}} =
               Sandboxes.start_agent_session(account, %{prompt: "Hello", agent_id: "agent_custom"})
    end

    test "refuses an environment without an API key" do
      account = account_fixture()
      agent_environment_fixture(account: account)

      reject(&ControlPlane.create_agent/2)
      reject(&ControlPlane.create_session/2)

      assert {:error, :missing_api_key} = Sandboxes.start_agent_session(account, %{prompt: "Hello"})
      assert [] = Sandboxes.list_agent_sessions(account)
    end

    test "needs exactly one enabled environment unless one is named" do
      account = account_fixture()

      assert {:error, :no_agent_environment} = Sandboxes.start_agent_session(account, %{prompt: "Hello"})

      agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api", enabled: false)
      assert {:error, :no_agent_environment} = Sandboxes.start_agent_session(account, %{prompt: "Hello"})

      first = agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api", anthropic_agent_id: "agent_1")
      agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api", anthropic_agent_id: "agent_2")
      assert {:error, :no_agent_environment} = Sandboxes.start_agent_session(account, %{prompt: "Hello"})

      foreign = agent_environment_fixture(anthropic_api_key: "sk-ant-api")

      assert {:error, :no_agent_environment} =
               Sandboxes.start_agent_session(account, %{prompt: "Hello", agent_environment_id: foreign.id})

      # Exactly one expected call also proves none of the refusals above
      # reached Anthropic.
      expect(ControlPlane, :create_session, fn "sk-ant-api", %{agent: "agent_1"} ->
        {:ok, %{"id" => "sesn_named", "status" => "running"}}
      end)

      assert {:ok, %AgentSession{agent_environment_id: id}} =
               Sandboxes.start_agent_session(account, %{prompt: "Hello", agent_environment_id: first.id})

      assert id == first.id
    end

    test "rejects invalid params before talking to Anthropic" do
      account = account_fixture()
      agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api", anthropic_agent_id: "agent_1")

      reject(&ControlPlane.create_agent/2)
      reject(&ControlPlane.create_session/2)

      assert {:error, %Ecto.Changeset{} = changeset} = Sandboxes.start_agent_session(account, %{})
      assert %{prompt: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               Sandboxes.start_agent_session(account, %{
                 prompt: "Hello",
                 repository_url: "git@github.com:tuist/tuist.git",
                 repository_ref: "main; rm -rf /",
                 budget_cents: 0
               })

      assert %{repository_url: [_url], repository_ref: [_ref], budget_cents: [_budget]} = errors_on(changeset)
    end

    test "surfaces Anthropic's rejection" do
      account = account_fixture()
      agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api", anthropic_agent_id: "agent_1")

      expect(ControlPlane, :create_session, fn _key, _attrs ->
        {:error, %{status: 404, message: "environment not found"}}
      end)

      assert {:error, %{status: 404, message: "environment not found"}} =
               Sandboxes.start_agent_session(account, %{prompt: "Hello"})

      assert [] = Sandboxes.list_agent_sessions(account)
    end
  end

  describe "get_agent_session/2" do
    test "scopes lookups to the account" do
      account = account_fixture()
      agent_session = agent_session_fixture(account: account)
      foreign = agent_session_fixture()

      assert {:ok, %AgentSession{id: id}} = Sandboxes.get_agent_session(account, agent_session.id)
      assert id == agent_session.id
      assert {:error, :not_found} = Sandboxes.get_agent_session(account, foreign.id)
      assert {:error, :not_found} = Sandboxes.get_agent_session(account, "not-a-uuid")
      assert %AgentSession{} = Sandboxes.get_agent_session!(account, agent_session.id)

      assert_raise Ecto.NoResultsError, fn -> Sandboxes.get_agent_session!(account, foreign.id) end
    end
  end

  describe "refresh_agent_session/1" do
    test "stores the status and the idle stop reason and reports usage and the sandbox state" do
      account = account_fixture()
      agent_environment = agent_environment_fixture(account: account, anthropic_api_key: "sk-ant-api")
      sandbox = sandbox_fixture(account: account, state: :paused)

      agent_session =
        agent_session_fixture(
          account: account,
          agent_environment: agent_environment,
          anthropic_session_id: "sesn_refresh",
          sandbox_id: sandbox.id
        )

      expect(ControlPlane, :get_session, fn "sk-ant-api", "sesn_refresh" ->
        {:ok,
         %{
           "id" => "sesn_refresh",
           "status" => "idle",
           "usage" => %{
             "input_tokens" => 10,
             "output_tokens" => 5,
             "cache_read_input_tokens" => 2,
             "active_seconds" => 3.5,
             "list_cost" => %{"amount" => "12", "currency" => "USD"}
           }
         }}
      end)

      expect(ControlPlane, :list_events, fn "sk-ant-api", "sesn_refresh", opts ->
        assert opts[:order] == "desc"

        {:ok,
         [
           %{"type" => "session.usage"},
           %{"type" => "session.status_idle", "stop_reason" => %{"type" => "end_turn"}},
           %{"type" => "session.status_idle", "stop_reason" => %{"type" => "requires_action"}}
         ]}
      end)

      assert {:ok, %{session: refreshed, status: "idle", usage: usage, sandbox_state: :paused}} =
               Sandboxes.refresh_agent_session(agent_session)

      assert usage == %{
               input_tokens: 10,
               output_tokens: 5,
               cache_read_input_tokens: 2,
               active_seconds: 3.5,
               list_cost: %{amount: "12", currency: "USD"}
             }

      assert %AgentSession{last_status: "idle", last_stop_reason: "end_turn"} = refreshed
      assert %AgentSession{last_status: "idle", last_stop_reason: "end_turn"} = Repo.reload!(agent_session)
    end

    test "keeps the previous stop reason while the session runs" do
      agent_session = agent_session_fixture(last_stop_reason: "end_turn")

      expect(ControlPlane, :get_session, fn _key, _id -> {:ok, %{"status" => "running"}} end)
      reject(&ControlPlane.list_events/3)

      assert {:ok, %{status: "running", usage: nil, sandbox_state: nil}} = Sandboxes.refresh_agent_session(agent_session)
      assert %AgentSession{last_status: "running", last_stop_reason: "end_turn"} = Repo.reload!(agent_session)
    end
  end

  describe "list_agent_session_events/2" do
    test "flattens the events, filters by index and remembers the stop reason" do
      agent_session = agent_session_fixture(anthropic_session_id: "sesn_events")

      events = [
        %{
          "type" => "user.message",
          "processed_at" => "2026-09-05T10:00:00Z",
          "content" => [%{"type" => "text", "text" => "Fix the build."}]
        },
        %{"type" => "agent.thinking", "processed_at" => "2026-09-05T10:00:01Z"},
        %{
          "type" => "agent.tool_use",
          "processed_at" => "2026-09-05T10:00:02Z",
          "name" => "bash",
          "input" => %{"command" => "swift build"}
        },
        %{
          "type" => "user.tool_result",
          "processed_at" => "2026-09-05T10:00:03Z",
          "tool_use_id" => "sevt_2",
          "content" => [%{"type" => "text", "text" => "error: missing module"}, %{"type" => "text", "text" => "exit 1"}]
        },
        %{
          "type" => "agent.message",
          "processed_at" => "2026-09-05T10:00:04Z",
          "content" => [%{"type" => "text", "text" => "Done."}, %{"type" => "redacted"}]
        },
        %{
          "type" => "session.status_idle",
          "processed_at" => "2026-09-05T10:00:05Z",
          "stop_reason" => %{"type" => "end_turn"}
        },
        %{"type" => "session.usage", "processed_at" => "2026-09-05T10:00:06Z", "usage" => %{"input_tokens" => 1}}
      ]

      expect(ControlPlane, :list_events, 2, fn "sk-ant-api-fixture", "sesn_events", [] -> {:ok, events} end)

      assert {:ok, %{events: all, next_after: 6}} = Sandboxes.list_agent_session_events(agent_session)
      assert Enum.map(all, & &1.index) == Enum.to_list(0..6)

      assert Enum.at(all, 0) == %{
               index: 0,
               type: "user.message",
               at: "2026-09-05T10:00:00Z",
               text: "Fix the build.",
               command: nil,
               tool_name: nil,
               stop_reason: nil
             }

      assert %{type: "agent.thinking", text: nil, command: nil, tool_name: nil} = Enum.at(all, 1)
      assert %{type: "agent.tool_use", tool_name: "bash", command: "swift build", text: nil} = Enum.at(all, 2)
      assert %{type: "user.tool_result", text: "error: missing module\nexit 1"} = Enum.at(all, 3)
      assert %{type: "agent.message", text: "Done."} = Enum.at(all, 4)
      assert %{type: "session.status_idle", stop_reason: "end_turn", at: "2026-09-05T10:00:05Z"} = Enum.at(all, 5)
      assert %{type: "session.usage", text: nil, stop_reason: nil} = Enum.at(all, 6)
      assert %AgentSession{last_stop_reason: "end_turn"} = Repo.reload!(agent_session)

      assert {:ok, %{events: newer, next_after: 6}} = Sandboxes.list_agent_session_events(agent_session, after: 4)
      assert Enum.map(newer, & &1.index) == [5, 6]
    end

    test "answers an empty list without moving the cursor" do
      agent_session = agent_session_fixture()
      expect(ControlPlane, :list_events, fn _key, _id, [] -> {:ok, []} end)

      assert {:ok, %{events: [], next_after: 3}} = Sandboxes.list_agent_session_events(agent_session, after: 3)
    end
  end

  describe "send_agent_session_message/2 and archive_agent_session/1" do
    test "send_agent_session_message/2 posts a user message" do
      agent_session = agent_session_fixture(anthropic_session_id: "sesn_message")

      expect(ControlPlane, :send_message, fn "sk-ant-api-fixture", "sesn_message", "Also run the tests." ->
        {:ok, %{"data" => [%{"id" => "sevt_9", "type" => "user.message"}]}}
      end)

      assert :ok = Sandboxes.send_agent_session_message(agent_session, "Also run the tests.")
    end

    test "send_agent_session_message/2 surfaces Anthropic errors and refuses without an API key" do
      agent_session = agent_session_fixture()

      expect(ControlPlane, :send_message, fn _key, _id, _text ->
        {:error, %{status: 404, message: "session not found"}}
      end)

      assert {:error, %{status: 404, message: "session not found"}} =
               Sandboxes.send_agent_session_message(agent_session, "Hello")

      account = account_fixture()
      keyless = agent_environment_fixture(account: account)
      agent_session = agent_session_fixture(account: account, agent_environment: keyless)
      reject(&ControlPlane.send_message/3)

      assert {:error, :missing_api_key} = Sandboxes.send_agent_session_message(agent_session, "Hello")
    end

    test "archive_agent_session/1 archives the session at Anthropic and marks the row" do
      agent_session = agent_session_fixture(anthropic_session_id: "sesn_archive")

      expect(ControlPlane, :archive_session, fn "sk-ant-api-fixture", "sesn_archive" ->
        {:ok, %{"id" => "sesn_archive", "archived_at" => "2026-09-05T10:00:00Z"}}
      end)

      assert {:ok, %AgentSession{last_status: "archived"}} = Sandboxes.archive_agent_session(agent_session)
      assert %AgentSession{last_status: "archived"} = Repo.reload!(agent_session)
    end
  end
end
