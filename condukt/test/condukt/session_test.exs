defmodule Condukt.SessionTest do
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.SessionStore.Memory
  alias Condukt.SessionStore.Snapshot
  alias Condukt.Test.LLMProvider
  alias ReqLLM.ToolCall

  defmodule ConfigAgent do
    use Condukt

    @impl true
    def system_prompt, do: "module prompt"

    @impl true
    def init(_opts) do
      {:ok, :ok}
    end
  end

  defmodule StoppingAgent do
    use Condukt

    @impl true
    def init(opts) do
      {:ok, %{test_pid: Keyword.fetch!(opts, :test_pid), stop_event: Keyword.get(opts, :stop_event, {:text, "stop"})}}
    end

    @impl true
    def handle_event(event, %{stop_event: event} = state) do
      send(state.test_pid, :callback_stopped)
      {:stop, :normal, state}
    end

    def handle_event(_event, state), do: {:noreply, state}
  end

  defmodule RecordingNotifier do
    @behaviour Condukt.Notifier

    @impl true
    def publish(_session_id, event, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:notified, event})
      :ok
    end
  end

  defmodule RecordingStore do
    @behaviour Condukt.SessionStore

    @impl true
    def load(opts) do
      maybe_send_store_opts(opts, :load)

      case Keyword.get(opts, :snapshot) do
        nil -> :not_found
        snapshot -> {:ok, snapshot}
      end
    end

    @impl true
    def save(snapshot, opts) do
      maybe_send_store_opts(opts, :save)
      send(Keyword.fetch!(opts, :test_pid), {:saved_snapshot, snapshot})
      :ok
    end

    @impl true
    def clear(opts) do
      maybe_send_store_opts(opts, :clear)
      send(Keyword.fetch!(opts, :test_pid), :cleared_snapshot)
      :ok
    end

    defp maybe_send_store_opts(opts, action) do
      case Keyword.get(opts, :opts_pid) do
        nil -> :ok
        pid -> send(pid, {:session_store_opts, action, Keyword.delete(opts, :opts_pid)})
      end
    end
  end

  defmodule HangingSession do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, :ok, opts)
    end

    @impl true
    def init(:ok), do: {:ok, :ok}

    @impl true
    def handle_call({:run, _prompt, _opts}, _from, state), do: {:noreply, state}
  end

  describe "run/3" do
    test "returns an error when a named session is missing" do
      assert {:error, {:session_exit, {:noproc, _call}}} =
               Condukt.Session.run(:missing_session, "go", timeout: 1)
    end

    test "returns an error when the session call times out" do
      pid = start_supervised!({HangingSession, []})

      assert {:error, {:session_exit, :timeout}} =
               Condukt.Session.run(pid, "go", timeout: 1)
    end
  end

  describe "session id" do
    test "generates a UUIDv7 by default" do
      {:ok, pid} = ConfigAgent.start_link(load_project_instructions: false)
      id = Condukt.Session.id(pid)

      assert is_binary(id)
      # 8-4-4-4-12 lowercase hex with version 7 in the third group.
      assert id =~ ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

      GenServer.stop(pid)
    end

    test "honors an :id option passed by the caller" do
      explicit = "11111111-2222-7333-8444-555555555555"
      {:ok, pid} = ConfigAgent.start_link(id: explicit, load_project_instructions: false)

      assert Condukt.Session.id(pid) == explicit

      GenServer.stop(pid)
    end

    test "tags agent telemetry with the session id" do
      handler_id = "agent-session-id-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [[:condukt, :agent, :start], [:condukt, :agent, :stop]],
        fn event, _measurements, metadata, _ ->
          send(test_pid, {:agent_telemetry, event, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {model, _} = LLMProvider.model([LLMProvider.text_response("hi")])

      {:ok, pid} = ConfigAgent.start_link(model: model, load_project_instructions: false)
      id = Condukt.Session.id(pid)

      assert {:ok, "hi"} = Condukt.run(pid, "ping")

      assert_receive {:agent_telemetry, [:condukt, :agent, :start], %{session_id: ^id, agent: ConfigAgent}}
      assert_receive {:agent_telemetry, [:condukt, :agent, :stop], %{session_id: ^id, agent: ConfigAgent}}

      GenServer.stop(pid)
    end

    test "tags tool_call telemetry with the session id" do
      handler_id = "tool-call-session-id-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [[:condukt, :tool_call, :start], [:condukt, :tool_call, :stop]],
        fn event, _measurements, metadata, _ ->
          send(test_pid, {:tool_telemetry, event, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      tool =
        Condukt.tool(
          name: "noop",
          description: "noop",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, _context -> {:ok, "ok"} end
        )

      tool_call = ToolCall.new("call_x", "noop", JSON.encode!(%{}))

      {model, _} =
        LLMProvider.model([
          LLMProvider.response(
            %ReqLLM.Message{role: :assistant, content: [], tool_calls: [tool_call]},
            :tool_calls
          ),
          LLMProvider.text_response("done")
        ])

      {:ok, pid} = ConfigAgent.start_link(model: model, tools: [tool], load_project_instructions: false)
      id = Condukt.Session.id(pid)

      assert {:ok, "done"} = Condukt.run(pid, "go")

      assert_receive {:tool_telemetry, [:condukt, :tool_call, :start],
                      %{session_id: ^id, tool: "noop", agent: ConfigAgent}}

      assert_receive {:tool_telemetry, [:condukt, :tool_call, :stop],
                      %{session_id: ^id, tool: "noop", agent: ConfigAgent}}

      GenServer.stop(pid)
    end

    test "tool_call telemetry includes args, tool_call_id, status and result on success" do
      handler_id = "tool-call-payload-ok-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [[:condukt, :tool_call, :start], [:condukt, :tool_call, :stop]],
        fn event, _measurements, metadata, _ ->
          send(test_pid, {:tool_telemetry, event, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      tool =
        Condukt.tool(
          name: "echo",
          description: "echoes a message",
          parameters: %{type: "object", properties: %{message: %{type: "string"}}, required: ["message"]},
          call: fn %{"message" => message}, _context -> {:ok, "echo: " <> message} end
        )

      tool_call = ToolCall.new("call_ok", "echo", JSON.encode!(%{"message" => "hi"}))

      {model, _} =
        LLMProvider.model([
          LLMProvider.response(
            %ReqLLM.Message{role: :assistant, content: [], tool_calls: [tool_call]},
            :tool_calls
          ),
          LLMProvider.text_response("done")
        ])

      {:ok, pid} = ConfigAgent.start_link(model: model, tools: [tool], load_project_instructions: false)

      assert {:ok, "done"} = Condukt.run(pid, "go")

      assert_receive {:tool_telemetry, [:condukt, :tool_call, :start],
                      %{tool: "echo", tool_call_id: "call_ok", args: %{"message" => "hi"}}}

      assert_receive {:tool_telemetry, [:condukt, :tool_call, :stop],
                      %{tool: "echo", tool_call_id: "call_ok", status: :ok, result: "echo: hi"}}

      GenServer.stop(pid)
    end

    test "tool_call telemetry surfaces :error status and the error tuple as :result" do
      handler_id = "tool-call-payload-error-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:condukt, :tool_call, :stop],
        fn _event, _measurements, metadata, _ ->
          send(test_pid, {:tool_telemetry, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      err_tool =
        Condukt.tool(
          name: "boom",
          description: "always errors",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, _context -> {:error, "kaboom"} end
        )

      err_call = ToolCall.new("call_err", "boom", JSON.encode!(%{}))

      # max_turns: 1 stops the loop after the first tool batch so the broken
      # error tuple never has to be re-serialized for a second LLM turn.
      {model, _} =
        LLMProvider.model([
          LLMProvider.response(
            %ReqLLM.Message{role: :assistant, content: [], tool_calls: [err_call]},
            :tool_calls
          )
        ])

      {:ok, pid} = ConfigAgent.start_link(model: model, tools: [err_tool], load_project_instructions: false)

      Condukt.run(pid, "go", max_turns: 1)

      assert_receive {:tool_telemetry,
                      %{tool: "boom", tool_call_id: "call_err", status: :error, result: {:error, "kaboom"}}}

      GenServer.stop(pid)
    end

    test "emits :llm_turn events with the conversation context and assistant response" do
      handler_id = "llm-turn-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [[:condukt, :llm_turn, :start], [:condukt, :llm_turn, :stop]],
        fn event, _measurements, metadata, _ ->
          send(test_pid, {:llm_turn, event, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {model, _} = LLMProvider.model([LLMProvider.text_response("hello back")])

      {:ok, pid} = ConfigAgent.start_link(model: model, load_project_instructions: false)
      id = Condukt.Session.id(pid)

      assert {:ok, "hello back"} = Condukt.run(pid, "hi there")

      assert_receive {:llm_turn, [:condukt, :llm_turn, :start],
                      %{
                        agent: ConfigAgent,
                        session_id: ^id,
                        turn: 0,
                        streaming?: false,
                        messages: messages,
                        tool_count: tool_count
                      }}

      assert is_list(messages)
      assert tool_count == 0
      assert Enum.any?(messages, fn msg -> msg.role == :user and Message.text(msg) == "hi there" end)

      assert_receive {:llm_turn, [:condukt, :llm_turn, :stop],
                      %{
                        agent: ConfigAgent,
                        session_id: ^id,
                        turn: 0,
                        status: :ok,
                        assistant_message: %Message{role: :assistant} = assistant_message
                      }}

      assert Message.text(assistant_message) == "hello back"

      GenServer.stop(pid)
    end

    test "emits one :llm_turn pair per loop iteration with increasing :turn" do
      handler_id = "llm-turn-multi-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach_many(
        handler_id,
        [[:condukt, :llm_turn, :start], [:condukt, :llm_turn, :stop]],
        fn event, _measurements, metadata, _ ->
          send(test_pid, {:llm_turn, event, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      tool =
        Condukt.tool(
          name: "noop",
          description: "noop",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, _context -> {:ok, "ok"} end
        )

      tool_call = ToolCall.new("call_z", "noop", JSON.encode!(%{}))

      {model, _} =
        LLMProvider.model([
          LLMProvider.response(
            %ReqLLM.Message{role: :assistant, content: [], tool_calls: [tool_call]},
            :tool_calls
          ),
          LLMProvider.text_response("done")
        ])

      {:ok, pid} = ConfigAgent.start_link(model: model, tools: [tool], load_project_instructions: false)

      assert {:ok, "done"} = Condukt.run(pid, "go")

      assert_receive {:llm_turn, [:condukt, :llm_turn, :start], %{turn: 0, tool_count: 1}}
      assert_receive {:llm_turn, [:condukt, :llm_turn, :stop], %{turn: 0, status: :ok}}
      assert_receive {:llm_turn, [:condukt, :llm_turn, :start], %{turn: 1, tool_count: 1}}
      assert_receive {:llm_turn, [:condukt, :llm_turn, :stop], %{turn: 1, status: :ok}}

      GenServer.stop(pid)
    end

    test "tool_call telemetry redacts session secrets from the result" do
      handler_id = "tool-call-redacted-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:condukt, :tool_call, :stop],
        fn _event, _measurements, metadata, _ ->
          send(test_pid, {:tool_telemetry, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      tool =
        Condukt.tool(
          name: "show_secret",
          description: "Returns a configured secret",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, _context -> {:ok, "secret-token"} end
        )

      tool_call = ToolCall.new("call_redacted", "show_secret", JSON.encode!(%{}))

      {model, _} =
        LLMProvider.model([
          LLMProvider.response(
            %ReqLLM.Message{role: :assistant, content: [], tool_calls: [tool_call]},
            :tool_calls
          ),
          LLMProvider.text_response("done")
        ])

      {:ok, pid} =
        ConfigAgent.start_link(
          model: model,
          tools: [tool],
          secrets: [GH_TOKEN: {:static, "secret-token"}],
          load_project_instructions: false
        )

      assert {:ok, "done"} = Condukt.run(pid, "go")

      assert_receive {:tool_telemetry, %{tool: "show_secret", status: :ok, result: result}}
      assert result == "[REDACTED:GH_TOKEN]"
      refute inspect(result) =~ "secret-token"

      GenServer.stop(pid)
    end

    test "secrets telemetry includes the session id" do
      handler_id = "secrets-session-id-#{inspect(make_ref())}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:condukt, :secrets, :resolve],
        fn _event, _measurements, metadata, _ ->
          send(test_pid, {:secret_telemetry, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, pid} =
        ConfigAgent.start_link(
          secrets: [GH_TOKEN: {:static, "secret-token"}],
          load_project_instructions: false
        )

      id = Condukt.Session.id(pid)

      assert_receive {:secret_telemetry, %{session_id: ^id, agent: ConfigAgent}}

      GenServer.stop(pid)
    end

    test "tools receive the session id in their context" do
      test_pid = self()

      tool =
        Condukt.tool(
          name: "echo_session",
          description: "echoes the session id",
          parameters: %{type: "object", properties: %{}},
          call: fn _args, context ->
            send(test_pid, {:tool_context, context})
            {:ok, "ok"}
          end
        )

      tool_call = ToolCall.new("call_y", "echo_session", JSON.encode!(%{}))

      {model, _} =
        LLMProvider.model([
          LLMProvider.response(
            %ReqLLM.Message{role: :assistant, content: [], tool_calls: [tool_call]},
            :tool_calls
          ),
          LLMProvider.text_response("done")
        ])

      {:ok, pid} = ConfigAgent.start_link(model: model, tools: [tool], load_project_instructions: false)
      id = Condukt.Session.id(pid)

      assert {:ok, "done"} = Condukt.run(pid, "go")

      assert_receive {:tool_context, %{session_id: ^id}}

      GenServer.stop(pid)
    end
  end

  test "transient sessions are not linked to the caller" do
    assert {:ok, {pid, links}} =
             Condukt.Session.with_transient(ConfigAgent, [load_project_instructions: false], fn pid ->
               {:ok, {pid, elem(Process.info(self(), :links), 1)}}
             end)

    refute pid in links
    refute Process.alive?(pid)
  end

  test "stores the configured :redactor on the session state" do
    {:ok, pid} =
      ConfigAgent.start_link(
        redactor: {Condukt.Redactors.Regex, extra_patterns: []},
        load_project_instructions: false
      )

    state = :sys.get_state(pid)
    assert state.redactor == {Condukt.Redactors.Regex, extra_patterns: []}

    GenServer.stop(pid)
  end

  test "redactor defaults to nil when no option is given" do
    {:ok, pid} = ConfigAgent.start_link(load_project_instructions: false)
    assert :sys.get_state(pid).redactor == nil
    GenServer.stop(pid)
  end

  test "stores resolved secrets on the session state" do
    {:ok, pid} =
      ConfigAgent.start_link(
        secrets: [GH_TOKEN: {:static, "secret-token"}],
        load_project_instructions: false
      )

    assert :sys.get_state(pid).secrets == %Condukt.Secrets{env: [{"GH_TOKEN", "secret-token"}]}

    GenServer.stop(pid)
  end

  test "emits telemetry when session secrets resolve" do
    handler_id = "secrets-resolve-test-#{inspect(make_ref())}"
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:condukt, :secrets, :resolve],
      fn event, measurements, metadata, _ ->
        send(test_pid, {:secret_telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, pid} =
      ConfigAgent.start_link(
        secrets: [GH_TOKEN: {:static, "secret-token"}, DATABASE_URL: {:static, "postgres://secret"}],
        load_project_instructions: false
      )

    assert_receive {:secret_telemetry, [:condukt, :secrets, :resolve], %{count: 2}, metadata}
    assert metadata.agent == ConfigAgent
    assert Enum.sort(metadata.names) == ["DATABASE_URL", "GH_TOKEN"]
    refute inspect(metadata) =~ "secret-token"
    refute inspect(metadata) =~ "postgres://secret"

    GenServer.stop(pid)
  end

  test "returns a secrets init failure when configured secrets cannot resolve" do
    previous = Process.flag(:trap_exit, true)

    on_exit(fn ->
      Process.flag(:trap_exit, previous)
    end)

    assert {:error, {:secrets_init_failed, :static_secret_requires_value}} =
             ConfigAgent.start_link(
               secrets: [API_TOKEN: {Condukt.Secrets.Providers.Static, []}],
               load_project_instructions: false
             )
  end

  test "redacts session secrets from tool results before the next model turn" do
    handler_id = "secrets-access-test-#{inspect(make_ref())}"
    test_pid = self()

    :telemetry.attach(
      handler_id,
      [:condukt, :secrets, :access],
      fn event, measurements, metadata, _ ->
        send(test_pid, {:secret_telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    tool =
      Condukt.tool(
        name: "show_secret",
        description: "Returns a configured secret",
        parameters: %{type: "object", properties: %{}},
        call: fn _args, _context -> {:ok, "secret-token"} end
      )

    tool_call = ToolCall.new("call_1", "show_secret", JSON.encode!(%{}))

    {model, model_id} =
      LLMProvider.model([
        LLMProvider.response(
          %ReqLLM.Message{role: :assistant, content: [], tool_calls: [tool_call]},
          :tool_calls
        ),
        LLMProvider.text_response("done")
      ])

    {:ok, pid} =
      ConfigAgent.start_link(
        model: model,
        tools: [tool],
        secrets: [GH_TOKEN: {:static, "secret-token"}],
        load_project_instructions: false
      )

    assert {:ok, "done"} = Condukt.run(pid, "call the tool")

    assert_receive {:secret_telemetry, [:condukt, :secrets, :access], %{count: 1}, metadata}
    assert metadata.agent == ConfigAgent
    assert metadata.tool == "show_secret"
    assert metadata.tool_call_id == "call_1"
    assert metadata.names == ["GH_TOKEN"]
    refute inspect(metadata) =~ "secret-token"

    assert_receive {LLMProvider, :request, ^model_id, _first_context, _first_opts}
    assert_receive {LLMProvider, :request, ^model_id, second_context, _second_opts}

    context_dump = inspect(second_context)
    assert context_dump =~ "[REDACTED:GH_TOKEN]"
    refute context_dump =~ "secret-token"

    assert Enum.any?(Condukt.history(pid), fn
             %Message{role: :tool_result, content: "[REDACTED:GH_TOKEN]"} -> true
             _ -> false
           end)

    GenServer.stop(pid)
  end

  # A reasoning model spends the output budget thinking before it writes any
  # answer, so a ceiling sized for the answer alone truncates the response
  # mid-thought and comes back with empty content.
  test "sends the configured output-token ceiling to the provider" do
    {model, model_id} = LLMProvider.model([LLMProvider.text_response("done")])

    {:ok, pid} =
      ConfigAgent.start_link(
        model: model,
        max_tokens: 16_384,
        load_project_instructions: false
      )

    assert {:ok, "done"} = Condukt.run(pid, "hello")
    assert_receive {LLMProvider, :request, ^model_id, _context, opts}
    assert opts[:max_tokens] == 16_384

    GenServer.stop(pid)
  end

  test "leaves the output-token ceiling to the provider when unset" do
    {model, model_id} = LLMProvider.model([LLMProvider.text_response("done")])

    {:ok, pid} = ConfigAgent.start_link(model: model, load_project_instructions: false)

    assert {:ok, "done"} = Condukt.run(pid, "hello")
    assert_receive {LLMProvider, :request, ^model_id, _context, opts}
    refute Keyword.has_key?(opts, :max_tokens)

    GenServer.stop(pid)
  end

  test "rejects invalid LLM request options before starting a session" do
    assert {:error, {:invalid_llm_request_options, %{headers: []}}} =
             ConfigAgent.start_link(llm_request_options: %{headers: []}, load_project_instructions: false)
  end

  test "reads the output-token ceiling from config when the option is omitted" do
    {model, model_id} = LLMProvider.model([LLMProvider.text_response("done")])

    {:ok, pid} =
      ConfigAgent.start_link(
        model: model,
        config: [max_tokens: 4_096],
        load_project_instructions: false
      )

    assert {:ok, "done"} = Condukt.run(pid, "hello")
    assert_receive {LLMProvider, :request, ^model_id, _context, opts}
    assert opts[:max_tokens] == 4_096

    GenServer.stop(pid)
  end

  test "uses config defaults when options are omitted" do
    {:ok, pid} =
      ConfigAgent.start_link(
        config: [
          api_key: "config-key",
          model: "openai:gpt-4o-mini",
          system_prompt: "config prompt",
          thinking_level: :low,
          cwd: "/tmp/agent"
        ],
        load_project_instructions: false
      )

    state = :sys.get_state(pid)

    assert state.llm.api_key == "config-key"
    assert state.llm.model == "openai:gpt-4o-mini"
    assert state.system_prompt == "config prompt"
    assert state.llm.thinking_level == :low
    assert state.cwd == "/tmp/agent"
    assert state.user_state == :ok

    GenServer.stop(pid)
  end

  test "start_link options override config values" do
    {:ok, pid} =
      ConfigAgent.start_link(
        config: [
          api_key: "config-key",
          system_prompt: "config prompt"
        ],
        api_key: "option-key",
        system_prompt: "option prompt",
        load_project_instructions: false
      )

    state = :sys.get_state(pid)

    assert state.llm.api_key == "option-key"
    assert state.system_prompt == "option prompt"
    assert state.user_state == :ok

    GenServer.stop(pid)
  end

  test "restores persisted session messages and settings when not explicitly configured" do
    snapshot = %Snapshot{
      messages: [Message.user("restored prompt"), Message.assistant("restored reply")],
      model: "openai:gpt-4o-mini",
      thinking_level: :low,
      system_prompt: "persisted prompt"
    }

    {:ok, pid} =
      ConfigAgent.start_link(
        session_store: {RecordingStore, snapshot: snapshot, test_pid: self()},
        load_project_instructions: false
      )

    state = :sys.get_state(pid)

    assert state.messages == snapshot.messages
    assert state.llm.model == snapshot.model
    assert state.llm.thinking_level == snapshot.thinking_level
    assert state.system_prompt == snapshot.system_prompt

    GenServer.stop(pid)
  end

  test "explicit options override restored session settings" do
    snapshot = %Snapshot{
      messages: [Message.user("restored prompt")],
      model: "openai:gpt-4o-mini",
      thinking_level: :low,
      system_prompt: "persisted prompt"
    }

    {:ok, pid} =
      ConfigAgent.start_link(
        model: "anthropic:claude-sonnet-4-20250514",
        thinking_level: :high,
        system_prompt: "explicit prompt",
        session_store: {RecordingStore, snapshot: snapshot, test_pid: self()},
        load_project_instructions: false
      )

    state = :sys.get_state(pid)

    assert state.messages == snapshot.messages
    assert state.llm.model == "anthropic:claude-sonnet-4-20250514"
    assert state.llm.thinking_level == :high
    assert state.system_prompt == "explicit prompt"

    GenServer.stop(pid)
  end

  test "clear removes persisted session state" do
    snapshot = %Snapshot{
      messages: [Message.user("restored prompt")],
      model: "openai:gpt-4o-mini",
      thinking_level: :low,
      system_prompt: "persisted prompt"
    }

    {:ok, pid} =
      ConfigAgent.start_link(
        session_store: {RecordingStore, snapshot: snapshot, test_pid: self()},
        load_project_instructions: false
      )

    assert :ok = Condukt.clear(pid)
    assert_receive :cleared_snapshot
    assert Condukt.history(pid) == []

    GenServer.stop(pid)
  end

  test "passes session store key and configured opts to callbacks" do
    key = {:telegram_chat, 123}

    {:ok, pid} =
      ConfigAgent.start_link(
        session_store: {RecordingStore, test_pid: self(), opts_pid: self()},
        session_store_key: key,
        session_store_opts: [caller: self(), key: :ignored],
        load_project_instructions: false
      )

    assert_receive {:session_store_opts, :load, load_opts}
    assert_store_opts(load_opts, key)

    assert :ok = Condukt.compact(pid)
    assert_receive {:session_store_opts, :save, save_opts}
    assert_store_opts(save_opts, key)

    assert :ok = Condukt.clear(pid)
    assert_receive {:session_store_opts, :clear, clear_opts}
    assert_store_opts(clear_opts, key)

    GenServer.stop(pid)
  end

  test "memory store restores snapshots by session_store_key independent of session id" do
    key = {:conversation, make_ref()}
    stored_message = Message.user("persist this conversation")

    assert Memory.load(key: key) == :not_found

    {:ok, first_pid} =
      ConfigAgent.start_link(
        id: "first-session",
        session_store: Memory,
        session_store_key: key,
        load_project_instructions: false
      )

    :sys.replace_state(first_pid, fn state ->
      %{state | messages: [stored_message]}
    end)

    assert :ok = Condukt.compact(first_pid)
    GenServer.stop(first_pid)

    {:ok, second_pid} =
      ConfigAgent.start_link(
        id: "second-session",
        session_store: Memory,
        session_store_key: key,
        load_project_instructions: false
      )

    assert Condukt.history(second_pid) == [stored_message]
    assert :ok = Condukt.clear(second_pid)
    assert Memory.load(key: key) == :not_found

    GenServer.stop(second_pid)
  end

  defmodule LastOneCompactor do
    @behaviour Condukt.Compactor

    @impl true
    def compact(messages, _opts) do
      {:ok, Enum.take(messages, -1)}
    end
  end

  defmodule GatedCompactor do
    @behaviour Condukt.Compactor

    @impl true
    def compact(messages, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:compacting, self(), messages, Condukt.TraceContext.current()})

      receive do
        {:finish, result} -> result
        :crash -> exit(:compactor_crashed)
      end
    end
  end

  describe "background compaction" do
    for mode <- [:run, :stream] do
      @tag mode: mode
      test "#{mode} adopts only between requests, retaining tool batches and newer messages", %{mode: mode} do
        test_pid = self()
        call = ToolCall.new("retained-call", "echo", JSON.encode!(%{}))

        wait = fn ->
          send(test_pid, {:inference, self()})
          receive do: (:continue -> :ok)
        end

        first =
          case mode do
            :run ->
              fn ->
                wait.()
                LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]}, :tool_calls)
              end

            :stream ->
              chunks =
                Stream.concat(
                  Stream.map([:start], fn _ ->
                    wait.()
                    ReqLLM.StreamChunk.text("working")
                  end),
                  [ReqLLM.StreamChunk.tool_call("echo", %{}, %{id: "retained-call", index: 0})]
                )

              compaction_stream(chunks, :tool_calls)
          end

        second =
          if mode == :run,
            do: LLMProvider.text_response("done"),
            else: compaction_stream([ReqLLM.StreamChunk.text("done")])

        tool =
          Condukt.tool(
            name: "echo",
            description: "echo",
            parameters: %{type: "object", properties: %{}},
            call: fn _, _ -> {:ok, "exact tool output"} end
          )

        old = Message.user(String.duplicate("o", 2_000))

        history = [
          old,
          Message.assistant([{:tool_call, "old-a", "echo", %{}}, {:tool_call, "old-b", "echo", %{}}]),
          Message.tool_result("old-a", "old output"),
          Message.tool_result("old-b", String.duplicate("r", 160)),
          Message.assistant("old answer")
        ]

        {pid, model_id} =
          background_session([first, second],
            tools: [tool],
            history: history,
            background_compaction: [context_window: 1_000, background_threshold: 0.5, keep_recent_tokens: 50]
          )

        trace = Condukt.TraceContext.new(trace_id: "0123456789abcdef0123456789abcdef", span_id: "0123456789abcdef")

        if mode == :stream do
          stub_stream(pid, model_id, [first, second])
        end

        task =
          Task.async(fn ->
            if mode == :run,
              do: Condukt.run(pid, "go", trace_context: trace),
              else: Condukt.stream(pid, "go", trace_context: trace) |> Enum.to_list()
          end)

        assert_receive {:compacting, worker, prefix, ^trace}
        assert_receive {:inference, inference}
        assert Enum.map(prefix, &Message.text/1) == [String.duplicate("o", 2_000)]
        monitor = Process.monitor(worker)
        send(worker, {:finish, {:ok, [Message.user("summary")]}})
        assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}

        # Completion during inference must not rewrite its history underneath it.
        assert hd(Condukt.history(pid)).content == String.duplicate("o", 2_000)
        send(inference, :continue)

        case mode do
          :run -> assert Task.await(task) == {:ok, "done"}
          :stream -> assert {:text, "done"} in Task.await(task)
        end

        request = if mode == :run, do: :request, else: :stream_request
        assert_receive {LLMProvider, ^request, ^model_id, first_context, _}
        assert_receive {LLMProvider, ^request, ^model_id, second_context, _}
        assert context_text(first_context) =~ String.duplicate("o", 2_000)
        refute context_text(second_context) =~ String.duplicate("o", 2_000)
        assert context_text(second_context) =~ "summary"
        assert context_text(second_context) =~ "old answer"
        assert Enum.any?(second_context.messages, &(&1.tool_call_id == "old-a"))
        assert Enum.any?(second_context.messages, &(&1.tool_call_id == "old-b"))
        assert Enum.any?(second_context.messages, &(&1.tool_call_id == "retained-call"))
        assert context_text(second_context) =~ "exact tool output"

        history = Condukt.history(pid)
        assert hd(history).content == "summary"
        assert List.last(history) |> Message.text() == "done"
        assert Enum.any?(history, &(&1.role == :tool_result and &1.tool_call_id == "retained-call"))
        assert_receive {:saved_snapshot, %Snapshot{messages: [%Message{content: "summary"} | _]}}
        GenServer.stop(pid)
      end
    end

    test "conversation continues during compaction, then waits for the same worker at the limit" do
      {pid, model_id} = background_session([LLMProvider.text_response("first"), LLMProvider.text_response("second")])

      assert Condukt.run(pid, "go") == {:ok, "first"}
      assert_receive {:compacting, worker, _prefix, _trace}
      assert_receive {LLMProvider, :request, ^model_id, _, _}

      prompt = String.duplicate("n", 2_000)
      task = Task.async(fn -> Condukt.run(pid, prompt) end)
      await_history(pid, &Enum.any?(&1, fn message -> message.content == prompt end))
      refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
      refute_receive {:compacting, _, _, _}, 20
      assert is_binary(Condukt.Session.id(pid))

      send(worker, {:finish, {:ok, [Message.user("summary")]}})
      assert Task.await(task) == {:ok, "second"}
      assert_receive {LLMProvider, :request, ^model_id, context, _}
      assert context_text(context) =~ "summary"
      assert context_text(context) =~ prompt
      assert context_text(context) =~ "first"
      GenServer.stop(pid)
    end

    for outcome <- [:failed, :insufficient] do
      @tag outcome: outcome
      @tag :capture_log
      test "#{outcome} background work falls back once over the expanded prefix", %{outcome: outcome} do
        answer = String.duplicate("a", 1_400)
        {pid, model_id} = background_session([LLMProvider.text_response(answer), LLMProvider.text_response("second")])
        assert Condukt.run(pid, "go") == {:ok, answer}
        assert_receive {:compacting, worker, prefix, _}
        assert_receive {LLMProvider, :request, ^model_id, _, _}

        prompt = String.duplicate("n", 400)
        task = Task.async(fn -> Condukt.run(pid, prompt) end)
        await_history(pid, &Enum.any?(&1, fn message -> message.content == prompt end))

        result = if outcome == :failed, do: {:error, :unavailable}, else: {:ok, prefix}
        send(worker, {:finish, result})
        assert_receive {:compacting, fallback, expanded, _}
        assert Enum.any?(expanded, &(Message.text(&1) == answer))
        refute Enum.any?(expanded, &(&1.content == prompt))
        refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
        send(fallback, {:finish, {:ok, [Message.user("fresh summary")]}})

        assert Task.await(task) == {:ok, "second"}
        assert_receive {LLMProvider, :request, ^model_id, context, _}
        assert context_text(context) =~ "fresh summary"
        assert context_text(context) =~ prompt
        refute context_text(context) =~ answer
        GenServer.stop(pid)
      end
    end

    for mode <- [:run, :stream], outcome <- [:error, :crash, :timeout, :unchanged] do
      @tag mode: mode, outcome: outcome
      @tag :capture_log
      test "#{mode} #{outcome} fallback preserves history and refuses an oversized inference request", %{
        mode: mode,
        outcome: outcome
      } do
        old = Message.user(String.duplicate("o", 4_000))
        timeout = if outcome == :timeout, do: 20, else: 5_000

        {pid, model_id} =
          background_session([LLMProvider.text_response("must not run")],
            history: [old, Message.assistant("old answer")],
            background_compaction: [context_window: 1_000, timeout: timeout]
          )

        task =
          Task.async(fn ->
            if mode == :run, do: Condukt.run(pid, "go"), else: Condukt.stream(pid, "go") |> Enum.to_list()
          end)

        assert_receive {:compacting, worker, prefix, _}

        case outcome do
          :error -> send(worker, {:finish, {:error, :unavailable}})
          :crash -> send(worker, :crash)
          :timeout -> :ok
          :unchanged -> send(worker, {:finish, {:ok, prefix}})
        end

        reason =
          %{error: :unavailable, crash: :compactor_crashed, timeout: :timeout, unchanged: :context_limit}[outcome]

        case mode do
          :run -> assert Task.await(task) == {:error, {:compaction_failed, reason}}
          :stream -> assert {:error, {:compaction_failed, reason}} in Task.await(task)
        end

        refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
        assert Enum.map(Condukt.history(pid), &Message.text/1) == [old.content, "old answer", "go"]
        GenServer.stop(pid)
      end
    end

    for mode <- [:run, :stream], cancellation <- [:clear, :abort], background <- [true, false] do
      @tag mode: mode, cancellation: cancellation, background: background
      test "#{mode} #{cancellation} rejects stale tools and history with background=#{background}", %{
        mode: mode,
        cancellation: cancellation,
        background: background
      } do
        test_pid = self()

        tool =
          Condukt.tool(
            name: "write",
            description: "write",
            parameters: %{type: "object", properties: %{}},
            call: fn _, _ ->
              send(test_pid, :stale_tool_executed)
              {:ok, "must not write"}
            end
          )

        wait = fn ->
          send(test_pid, {:inference, self()})
          receive do: (:continue -> :ok)
        end

        first =
          case mode do
            :run ->
              fn ->
                wait.()
                call = ToolCall.new("stale-call", "write", JSON.encode!(%{}))
                LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]}, :tool_calls)
              end

            :stream ->
              chunks =
                Stream.map([:tools], fn _ ->
                  wait.()
                  ReqLLM.StreamChunk.tool_call("write", %{}, %{id: "stale-call", index: 0})
                end)

              compaction_stream(chunks, :tool_calls)
          end

        second =
          if mode == :run,
            do: LLMProvider.text_response("new answer"),
            else: compaction_stream([ReqLLM.StreamChunk.text("new answer")])

        opts = if background, do: [], else: [background_compaction: false, compactor: nil]
        {pid, model_id} = background_session([first, second, second], Keyword.put(opts, :tools, [tool]))
        if mode == :stream, do: stub_stream(pid, model_id, [first, second, second])

        task =
          Task.async(fn ->
            if mode == :run, do: Condukt.run(pid, "go"), else: Condukt.stream(pid, "go") |> Enum.to_list()
          end)

        worker =
          if background do
            assert_receive {:compacting, worker, _, _}
            worker
          end

        assert_receive {:inference, inference}, 1_000
        on_exit(fn -> send(inference, :continue) end)
        inference_monitor = Process.monitor(inference)
        monitor = if worker, do: Process.monitor(worker)
        assert :ok = apply(Condukt, cancellation, [pid])
        assert {:ok, cancelled_result} = Task.yield(task, 500)

        if cancellation == :clear do
          if worker, do: assert_receive({:DOWN, ^monitor, :process, ^worker, _})
          assert Condukt.history(pid) == []
        end

        case mode do
          :run -> assert Condukt.run(pid, "new prompt") == {:ok, "new answer"}
          :stream -> assert {:text, "new answer"} in (Condukt.stream(pid, "new prompt") |> Enum.to_list())
        end

        if worker && cancellation == :abort do
          send(worker, {:finish, {:ok, [Message.user("reused summary")]}})
          await_history(pid, &(hd(&1).content == "reused summary"))
        end

        history = Condukt.history(pid)
        assert history |> List.last() |> Message.text() == "new answer"
        send(inference, :continue)
        assert_receive {:DOWN, ^inference_monitor, :process, ^inference, :normal}, 1_000

        case mode do
          :run ->
            assert cancelled_result == {:error, :aborted}

          :stream ->
            assert {:error, :aborted} in cancelled_result
            refute Enum.any?(cancelled_result, &match?({:tool_call, _, _, _}, &1))
        end

        refute_receive :stale_tool_executed, 20
        assert Condukt.history(pid) == history
        GenServer.stop(pid)
      end
    end

    for overlap <- [false, true] do
      @tag overlap: overlap
      test "callback stop preserves compaction and fences late events with replacement overlap=#{overlap}", %{
        overlap: overlap
      } do
        test_pid = self()

        tool =
          Condukt.tool(
            name: "write",
            description: "write",
            parameters: %{type: "object", properties: %{}},
            call: fn _, _ ->
              send(test_pid, :stale_tool_executed)
              {:ok, "must not write"}
            end
          )

        late_chunks =
          Stream.concat(
            Stream.map([:late], fn _ ->
              send(test_pid, {:old_inference, self()})
              receive do: (:continue -> ReqLLM.StreamChunk.text("stop"))
            end),
            [ReqLLM.StreamChunk.tool_call("write", %{}, %{id: "stale-call", index: 0})]
          )

        first = compaction_stream(Stream.concat([ReqLLM.StreamChunk.text("stop")], late_chunks), :tool_calls)

        second =
          if overlap do
            compaction_stream(
              Stream.map([:replacement], fn _ ->
                send(test_pid, {:new_inference, self()})
                receive do: (:continue -> ReqLLM.StreamChunk.text("new answer"))
              end)
            )
          else
            compaction_stream([ReqLLM.StreamChunk.text("new answer")])
          end

        {pid, model_id} =
          background_session([],
            agent: StoppingAgent,
            test_pid: test_pid,
            tools: [tool],
            notifier: {RecordingNotifier, test_pid: test_pid}
          )

        stub_stream(pid, model_id, [first, second])
        task = Task.async(fn -> Condukt.stream(pid, "go") |> Enum.to_list() end)
        assert_receive {:compacting, worker, _, _}, 1_000
        assert_receive :callback_stopped, 1_000
        assert_receive {:old_inference, old_inference}, 1_000
        on_exit(fn -> send(old_inference, :continue) end)
        old_monitor = Process.monitor(old_inference)
        assert {:ok, cancelled_events} = Task.yield(task, 500)
        assert {:text, "stop"} in cancelled_events
        assert {:error, :aborted} in cancelled_events
        assert_receive {:notified, {:error, :aborted}}
        assert_receive {:notified, :done}
        send(worker, {:finish, {:ok, [Message.user("adopted summary")]}})
        await_history(pid, &(hd(&1).content == "adopted summary"))

        {replacement, new_inference} =
          if overlap do
            task = Task.async(fn -> Condukt.stream(pid, "new prompt") |> Enum.to_list() end)
            assert_receive {:new_inference, new_inference}
            {task, new_inference}
          else
            {nil, nil}
          end

        send(old_inference, :continue)
        assert_receive {:DOWN, ^old_monitor, :process, ^old_inference, :normal}, 1_000
        refute_receive :callback_stopped, 20
        refute_receive :stale_tool_executed, 20
        refute_receive {:notified, :done}, 20
        assert hd(Condukt.history(pid)).content == "adopted summary"

        if overlap do
          send(new_inference, :continue)
          assert {:text, "new answer"} in Task.await(replacement)
        else
          assert {:text, "new answer"} in (Condukt.stream(pid, "new prompt") |> Enum.to_list())
        end

        assert Enum.map(Condukt.history(pid), &Message.text/1) ==
                 ["adopted summary", "old answer", "go", "new prompt", "new answer"]

        assert_receive {:notified, {:text, "new answer"}}
        assert_receive {:notified, :done}
        GenServer.stop(pid)
      end
    end

    test "callback stop at turn_start prevents the first provider request" do
      {pid, model_id} =
        background_session([],
          agent: StoppingAgent,
          test_pid: self(),
          stop_event: :turn_start,
          background_compaction: false,
          compactor: nil
        )

      stub_stream(pid, model_id, [compaction_stream([ReqLLM.StreamChunk.text("must not request")])])
      events = Condukt.stream(pid, "go") |> Enum.to_list()
      assert_receive :callback_stopped
      assert {:error, :aborted} in events
      refute_receive {LLMProvider, :stream_request, ^model_id, _, _}, 20
      GenServer.stop(pid)
    end

    for mode <- [:run, :stream] do
      @tag mode: mode
      test "#{mode} abort interrupts retry backoff without another provider request", %{mode: mode} do
        test_pid = self()
        error = {:error, %ReqLLM.Error.API.Request{status: 503, reason: "overloaded"}}

        retry = [
          base_delay_ms: 5_000,
          max_delay_ms: 5_000,
          classify: fn _reason ->
            send(test_pid, {:backoff, self()})
            :retry
          end
        ]

        {pid, model_id} =
          background_session([error, LLMProvider.text_response("must not retry")],
            retry: retry,
            background_compaction: false,
            compactor: nil
          )

        if mode == :stream do
          stub_stream(pid, model_id, [error, compaction_stream([ReqLLM.StreamChunk.text("must not retry")])])
        end

        task =
          Task.async(fn ->
            if mode == :run, do: Condukt.run(pid, "go"), else: Condukt.stream(pid, "go") |> Enum.to_list()
          end)

        assert_receive {:backoff, worker}
        monitor = Process.monitor(worker)
        request = if mode == :run, do: :request, else: :stream_request
        assert_receive {LLMProvider, ^request, ^model_id, _, _}
        assert Condukt.abort(pid) == :ok
        assert {:ok, result} = Task.yield(task, 500)

        case mode do
          :run -> assert result == {:error, :aborted}
          :stream -> assert {:error, :aborted} in result
        end

        assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
        refute_receive {LLMProvider, ^request, ^model_id, _, _}, 20
        GenServer.stop(pid)
      end
    end

    test "a rejected stream does not publish completion for the active turn" do
      test_pid = self()

      first =
        compaction_stream(
          Stream.map([:waiting], fn _ ->
            send(test_pid, {:inference, self()})
            receive do: (:continue -> ReqLLM.StreamChunk.text("active answer"))
          end)
        )

      {pid, model_id} =
        background_session([],
          history: [],
          notifier: {RecordingNotifier, test_pid: test_pid}
        )

      stub_stream(pid, model_id, [first])
      active = Task.async(fn -> Condukt.stream(pid, "active prompt") |> Enum.to_list() end)
      assert_receive {:inference, inference}
      on_exit(fn -> send(inference, :continue) end)
      assert Condukt.run(pid, "rejected run") == {:error, :already_streaming}
      assert Condukt.stream(pid, "rejected stream") |> Enum.to_list() == [{:error, :already_streaming}]
      refute_receive {:notified, {:error, :already_streaming}}, 20
      refute_receive {:notified, :done}, 20
      send(inference, :continue)
      assert {:text, "active answer"} in Task.await(active)
      assert_receive {:notified, :done}
      assert Enum.map(Condukt.history(pid), &Message.text/1) == ["active prompt", "active answer"]
      GenServer.stop(pid)
    end

    test "abort releases a blocking checkpoint without cancelling reusable background work" do
      {pid, _model_id} = background_session([LLMProvider.text_response("first")])
      assert Condukt.run(pid, "go") == {:ok, "first"}
      assert_receive {:compacting, worker, _, _}

      prompt = String.duplicate("n", 2_000)
      task = Task.async(fn -> Condukt.run(pid, prompt) end)
      await_history(pid, &Enum.any?(&1, fn message -> message.content == prompt end))
      assert :ok = Condukt.abort(pid)
      assert Task.await(task) == {:error, :aborted}
      assert Process.alive?(worker)

      monitor = Process.monitor(worker)
      GenServer.stop(pid)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}
    end

    for {format, usage, compact?} <- [
          {:uncached, %{input_tokens: 700}, true},
          {:separate_cache, %{input_tokens: 30, cache_read_input_tokens: 420, cache_creation_input_tokens: 250}, true},
          {:normalized_separate_cache,
           %{input_tokens: 30, cached_tokens: 420, cache_creation_tokens: 250, input_includes_cached: false}, true},
          {:included_cache,
           %{input_tokens: 400, cached_tokens: 200, cache_creation_tokens: 150, input_includes_cached: true}, false}
        ] do
      @tag usage: usage, compact?: compact?
      test "counts #{format} input usage without omitting or double-counting cached context", %{
        usage: usage,
        compact?: compact?
      } do
        response = %{LLMProvider.text_response("answer") | usage: usage}

        {pid, _model_id} =
          background_session([response],
            history: [],
            background_compaction: [context_window: 1_000, keep_recent_tokens: 0]
          )

        assert Condukt.run(pid, "small prompt") == {:ok, "answer"}

        if compact? do
          assert_receive {:compacting, _worker, [%Message{content: "small prompt"}], _}
        else
          refute_receive {:compacting, _, _, _}, 20
        end

        GenServer.stop(pid)
      end
    end

    test "idle completion persists the adopted history and restores it without pending work" do
      {pid, _model_id} = background_session([LLMProvider.text_response("answer")])
      assert Condukt.run(pid, "go") == {:ok, "answer"}
      assert_receive {:compacting, worker, _prefix, _trace}
      send(worker, {:finish, {:ok, [Message.user("idle summary")]}})
      history = await_history(pid, &(hd(&1).content == "idle summary"))
      assert Enum.map(history, &Message.text/1) == ["idle summary", "old answer", "go", "answer"]
      assert_receive {:saved_snapshot, %Snapshot{messages: ^history} = snapshot}
      GenServer.stop(pid)

      {restored, _model_id} =
        background_session([], session_store: {RecordingStore, test_pid: self(), snapshot: snapshot})

      assert Condukt.history(restored) == history
      refute_receive {:compacting, _, _, _}, 20
      GenServer.stop(restored)
    end

    for overhead <- [:system_prompt, :tools, :max_tokens] do
      @tag overhead: overhead
      test "reserves #{overhead} before deciding whether inference fits", %{overhead: overhead} do
        tool =
          Condukt.tool(
            name: "echo",
            description: String.duplicate("t", 1_600),
            parameters: %{type: "object", properties: %{}},
            call: fn _, _ -> {:ok, "unused"} end
          )

        value = %{system_prompt: String.duplicate("s", 1_600), tools: [tool], max_tokens: 400}[overhead]
        {pid, model_id} = background_session([LLMProvider.text_response("answer")], [{overhead, value}])
        task = Task.async(fn -> Condukt.run(pid, "go") end)
        assert_receive {:compacting, worker, _prefix, _trace}
        refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
        send(worker, {:finish, {:ok, [Message.user("summary")]}})
        assert Task.await(task) == {:ok, "answer"}
        assert_receive {LLMProvider, :request, ^model_id, context, _}
        assert context_text(context) =~ "summary"
        refute context_text(context) =~ String.duplicate("o", 2_000)
        GenServer.stop(pid)
      end
    end

    test "manual compaction waits without blocking history reads and persists its result" do
      {pid, _model_id} = background_session([])
      task = Task.async(fn -> Condukt.compact(pid) end)
      assert_receive {:compacting, worker, original, _}
      assert Condukt.history(pid) == original
      assert Condukt.run(pid, "go") == {:error, :already_streaming}
      send(worker, {:finish, {:ok, [Message.user("manual summary")]}})
      assert Task.await(task) == :ok
      assert Enum.map(Condukt.history(pid), &Message.text/1) == ["manual summary"]
      assert_receive {:saved_snapshot, %Snapshot{messages: [%Message{content: "manual summary"}]}}
      GenServer.stop(pid)
    end

    test "refuses a tool-heavy turn rather than compacting its active prompt" do
      prompt = "LATEST:" <> String.duplicate("x", 3_193)
      call = ToolCall.new("c", "lookup", JSON.encode!(%{}))
      first = LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]}, :tool_calls)

      tool =
        Condukt.tool(
          name: "lookup",
          description: "lookup",
          parameters: %{type: "object", properties: %{}},
          call: fn _, _ -> {:ok, String.duplicate("r", 800)} end
        )

      {pid, model_id} =
        background_session([first, LLMProvider.text_response("must not request")],
          history: [],
          tools: [tool],
          compactor: {Condukt.Compactor.Sliding, keep: 0},
          background_compaction: [context_window: 1_000]
        )

      assert Condukt.run(pid, prompt) == {:error, {:compaction_failed, :context_limit}}
      assert_receive {LLMProvider, :request, ^model_id, context, _}
      assert context_text(context) =~ prompt
      refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
      assert hd(Condukt.history(pid)).content == prompt
      GenServer.stop(pid)
    end

    test "speculative work cannot include the active prompt after a tool batch" do
      test_pid = self()
      call = ToolCall.new("c", "lookup", JSON.encode!(%{}))
      first = LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]}, :tool_calls)

      second = fn ->
        send(test_pid, {:inference, self()})
        receive do: (:continue -> LLMProvider.text_response("done"))
      end

      tool =
        Condukt.tool(
          name: "lookup",
          description: "lookup",
          parameters: %{type: "object", properties: %{}},
          call: fn _, _ -> {:ok, String.duplicate("r", 800)} end
        )

      {pid, _model_id} =
        background_session([first, second],
          history: [],
          tools: [tool],
          background_compaction: [context_window: 1_000, keep_recent_tokens: 0]
        )

      prompt = String.duplicate("p", 2_000)
      task = Task.async(fn -> Condukt.run(pid, prompt) end)
      assert_receive {:inference, inference}
      on_exit(fn -> send(inference, :continue) end)
      refute_receive {:compacting, _, _, _}, 20
      send(inference, :continue)
      assert Task.await(task) == {:ok, "done"}
      assert hd(Condukt.history(pid)).content == prompt
      GenServer.stop(pid)
    end

    test "structured and encoded tool payloads enforce the same context limit" do
      structured = List.duplicate(%{}, 20_000)

      for output <- [structured, JSON.encode!(structured)] do
        call = ToolCall.new("c", "lookup", JSON.encode!(%{}))

        first =
          %{
            LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]}, :tool_calls)
            | usage: %{input_tokens: 100}
          }

        tool =
          Condukt.tool(
            name: "lookup",
            description: "lookup",
            parameters: %{type: "object", properties: %{}},
            call: fn _, _ -> {:ok, output} end
          )

        {pid, model_id} =
          background_session([first, LLMProvider.text_response("must not request")],
            history: [],
            tools: [tool],
            compactor: {Condukt.Compactor.Sliding, keep: 0}
          )

        assert Condukt.run(pid, "go") == {:error, {:compaction_failed, :context_limit}}
        assert_receive {LLMProvider, :request, ^model_id, _, _}
        refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
        assert List.last(Condukt.history(pid)).content == output
        GenServer.stop(pid)
      end
    end

    test "provider-valid tool errors containing process terms do not crash accounting" do
      call = ToolCall.new("c", "lookup", JSON.encode!(%{}))
      first = LLMProvider.response(%ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]}, :tool_calls)

      tool =
        Condukt.tool(
          name: "lookup",
          description: "lookup",
          parameters: %{type: "object", properties: %{}},
          call: fn _, _ -> {:error, {:could_not_contact, self()}} end
        )

      {pid, model_id} = background_session([first, LLMProvider.text_response("done")], history: [], tools: [tool])
      assert Condukt.run(pid, "go") == {:ok, "done"}
      assert_receive {LLMProvider, :request, ^model_id, _, _}
      assert_receive {LLMProvider, :request, ^model_id, context, _}
      assert context_text(context) =~ "Error: {:could_not_contact, #PID<"
      GenServer.stop(pid)
    end

    test "uses the restored model's context window, even when the default has none" do
      for default_window <- [10_000, nil] do
        {model, model_id} = LLMProvider.model([LLMProvider.text_response("must not request")])
        saved_model = Map.put(model, :limits, %{context: 1_000})
        default_model = %{provider: :condukt_test, id: "default", limits: %{context: default_window}}

        {:ok, pid} =
          ConfigAgent.start_link(
            config: [model: default_model],
            system_prompt: nil,
            session_store: {RecordingStore, test_pid: self(), snapshot: %Snapshot{model: saved_model}},
            compactor: {Condukt.Compactor.Sliding, keep: 0},
            background_compaction: true,
            load_project_instructions: false
          )

        assert Condukt.run(pid, String.duplicate("p", 8_000)) == {:error, {:compaction_failed, :context_limit}}
        refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
        GenServer.stop(pid)
      end
    end

    test "reserves effective max_tokens with the same precedence as inference" do
      for {top_level, request_option, expected} <- [
            {nil, 1_100, {:error, {:compaction_failed, :context_limit}}},
            {50, 1_100, {:ok, "done"}},
            {1_100, 50, {:error, {:compaction_failed, :context_limit}}}
          ] do
        {pid, model_id} =
          background_session([LLMProvider.text_response("done")],
            history: [],
            max_tokens: top_level,
            llm_request_options: [max_tokens: request_option]
          )

        assert Condukt.run(pid, "go") == expected

        if match?({:ok, _}, expected) do
          assert_receive {LLMProvider, :request, ^model_id, _, opts}
          assert opts[:max_tokens] == 50
        else
          refute_receive {LLMProvider, :request, ^model_id, _, _}, 20
        end

        GenServer.stop(pid)
      end
    end

    test "rejects invalid background policies before starting a session" do
      for policy <- [true, [context_window: 0], [context_window: 1_000, background_threshold: 0.95], [:invalid]] do
        assert {:error, {:invalid_background_compaction, _}} =
                 ConfigAgent.start_link(
                   compactor: LastOneCompactor,
                   model: %{provider: :condukt_test, id: "unknown-window"},
                   background_compaction: policy,
                   load_project_instructions: false
                 )
      end
    end
  end

  test "compactor is applied after stream_complete and the trimmed history is persisted" do
    ref = make_ref()
    messages = [Message.user("a"), Message.assistant("b"), Message.user("c"), Message.assistant("d")]

    state = %Condukt.Session{
      agent_module: ConfigAgent,
      llm: %{model: "openai:gpt-4o-mini", thinking_level: :medium},
      configured_system_prompt: "prompt",
      system_prompt: "prompt",
      cwd: "/tmp/agent",
      session_store: {RecordingStore, test_pid: self()},
      compaction: %Condukt.Session.Compaction{spec: LastOneCompactor},
      project_context: %{agents_md: nil, skills: [], prompt: nil},
      user_state: :ok
    }

    handler_id = "compact-test-#{inspect(ref)}"

    :telemetry.attach(
      handler_id,
      [:condukt, :compact, :stop],
      fn _event, measurements, metadata, _ ->
        send(self(), {:compact_telemetry, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:noreply, updated_state} =
             Condukt.Session.handle_cast(
               {:stream_complete, ref, {:ok, messages, "d", %{}}},
               state
             )

    assert length(updated_state.messages) == 1
    assert hd(updated_state.messages).content == "d"

    assert_receive {:saved_snapshot, %Snapshot{messages: persisted}}
    assert length(persisted) == 1

    assert_receive {:compact_telemetry, %{before: 4, after: 1, duration: _}, %{agent: ConfigAgent}}
  end

  test "compact/1 is a no-op when no compactor is configured" do
    {:ok, pid} =
      ConfigAgent.start_link(load_project_instructions: false)

    assert :ok = Condukt.compact(pid)

    GenServer.stop(pid)
  end

  test "compact/1 trims history using the configured compactor" do
    {:ok, pid} =
      ConfigAgent.start_link(
        compactor: LastOneCompactor,
        load_project_instructions: false
      )

    :sys.replace_state(pid, fn s ->
      %{s | messages: [Message.user("a"), Message.user("b"), Message.user("c")]}
    end)

    assert :ok = Condukt.compact(pid)
    history = Condukt.history(pid)
    assert length(history) == 1
    assert hd(history).content == "c"

    GenServer.stop(pid)
  end

  test "stream completion updates history and persists the final snapshot" do
    ref = make_ref()
    messages = [Message.user("hello"), Message.assistant("world")]

    state = %Condukt.Session{
      agent_module: ConfigAgent,
      llm: %{model: "openai:gpt-4o-mini", thinking_level: :medium},
      configured_system_prompt: "prompt",
      system_prompt: "prompt\n\n## Project Instructions\n\nUse mix test.",
      cwd: "/tmp/agent",
      session_store: {RecordingStore, test_pid: self()},
      project_context: %{agents_md: nil, skills: [], prompt: nil},
      user_state: :ok
    }

    assert {:noreply, updated_state} =
             Condukt.Session.handle_cast(
               {:stream_complete, ref, {:ok, messages, "world", %{}}},
               state
             )

    assert updated_state.messages == messages

    assert_receive {:saved_snapshot,
                    %Snapshot{
                      messages: ^messages,
                      model: "openai:gpt-4o-mini",
                      thinking_level: :medium,
                      system_prompt: "prompt"
                    }}
  end

  @tag :tmp_dir
  test "discovers project instructions and local skills from the project root", %{tmp_dir: cwd} do
    File.write!(Path.join(cwd, "AGENTS.md"), "Always run project checks.")

    skill_dir = Path.join(cwd, ".agents/skills/release")
    File.mkdir_p!(skill_dir)

    File.write!(
      Path.join(skill_dir, "SKILL.md"),
      """
      ---
      description: Prepare a release safely.
      ---

      Verify the changelog and version before releasing.
      """
    )

    {:ok, pid} =
      ConfigAgent.start_link(
        cwd: cwd,
        system_prompt: "base prompt"
      )

    state = :sys.get_state(pid)

    assert state.configured_system_prompt == "base prompt"
    assert state.system_prompt =~ "base prompt"
    assert state.system_prompt =~ "Always run project checks."
    assert state.system_prompt =~ ".agents/skills/release/SKILL.md"

    assert state.project_context.skills == [
             %Condukt.Context.Skill{
               name: "release",
               path: ".agents/skills/release/SKILL.md",
               description: "Prepare a release safely."
             }
           ]

    GenServer.stop(pid)
  end

  @tag :tmp_dir
  test "project instructions can be disabled", %{tmp_dir: cwd} do
    File.write!(Path.join(cwd, "AGENTS.md"), "Do not leak into the prompt.")

    {:ok, pid} =
      ConfigAgent.start_link(
        cwd: cwd,
        system_prompt: "base prompt",
        load_project_instructions: false
      )

    state = :sys.get_state(pid)

    assert state.system_prompt == "base prompt"
    assert state.project_context == %{agents_md: nil, skills: [], prompt: nil}

    GenServer.stop(pid)
  end

  defp background_session(responses, opts \\ []) do
    {model, model_id} = LLMProvider.model(responses)
    history = Keyword.get(opts, :history, [Message.user(String.duplicate("o", 2_000)), Message.assistant("old answer")])
    agent = Keyword.get(opts, :agent, ConfigAgent)

    defaults = [
      model: model,
      system_prompt: nil,
      compactor: {GatedCompactor, test_pid: self()},
      background_compaction: [context_window: 1_000, background_threshold: 0.5, keep_recent_tokens: 20],
      session_store: {RecordingStore, test_pid: self(), snapshot: %Snapshot{messages: history}},
      load_project_instructions: false
    ]

    {:ok, pid} = agent.start_link(Keyword.merge(defaults, Keyword.drop(opts, [:history, :agent])))
    {pid, model_id}
  end

  defp stub_stream(pid, model_id, responses) do
    test_pid = self()
    responses = start_supervised!({Agent, fn -> responses end})

    Mimic.stub(ReqLLM, :stream_text, fn model, context, opts ->
      send(test_pid, {LLMProvider, :stream_request, model_id, context, opts})
      response = Agent.get_and_update(responses, fn [response | rest] -> {response, rest} end)

      case response do
        {:error, _} = error -> error
        response -> {:ok, %{response | model: ReqLLM.model!(model), context: context}}
      end
    end)

    Mimic.allow(ReqLLM, self(), pid)
  end

  defp compaction_stream(chunks, finish_reason \\ :stop) do
    metadata =
      start_supervised!({ReqLLM.StreamResponse.MetadataHandle, fn -> %{finish_reason: finish_reason} end},
        id: make_ref()
      )

    %ReqLLM.StreamResponse{
      stream: chunks,
      metadata_handle: metadata,
      cancel: fn -> :ok end,
      model: nil,
      context: nil
    }
  end

  defp context_text(context) do
    context.messages
    |> Enum.flat_map(& &1.content)
    |> Enum.map_join("\n", &(&1.text || ""))
  end

  defp await_history(pid, predicate, attempts \\ 200) do
    history = Condukt.history(pid)

    if predicate.(history) or attempts == 0 do
      assert predicate.(history)
      history
    else
      Process.sleep(5)
      await_history(pid, predicate, attempts - 1)
    end
  end

  defp assert_store_opts(opts, key) do
    assert Keyword.fetch!(opts, :agent_module) == ConfigAgent
    assert is_binary(Keyword.fetch!(opts, :cwd))
    assert Keyword.fetch!(opts, :caller) == self()
    assert Keyword.fetch!(opts, :key) == key
  end
end
