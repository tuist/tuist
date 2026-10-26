defmodule Atlas.LLMs.RunnerTest do
  use Atlas.DataCase, async: true

  alias Atlas.Documents.Agents.DocumentClassifierAgent
  alias Atlas.LLMs.LocalTransport
  alias Atlas.LLMs.Runner
  alias Atlas.Slack.ConversationAgent
  alias Condukt.AgentRuntimes.Native
  alias Condukt.AnonymousAgent
  alias Condukt.Sandbox.Local
  alias Condukt.Tool
  alias Condukt.Tools.Command

  test "configuration does not override Condukt execution in any environment" do
    config_glob = Path.join(Path.dirname(Mix.Project.project_file()), "config/**/*.exs")

    for path <- Path.wildcard(config_glob) do
      ast = path |> File.read!() |> Code.string_to_quoted!()

      {_ast, configured?} =
        Macro.prewalk(ast, false, fn
          {:config, _meta, [:condukt | _args]} = node, _configured? -> {node, true}
          {{:., _meta, [_module, :config]}, _call_meta, [:condukt | _args]} = node, _configured? -> {node, true}
          node, configured? -> {node, configured?}
        end)

      refute configured?, "#{path} must not implicitly configure Condukt execution"
    end
  end

  test "built-in agent callbacks use in-process execution without coding tools or remote sandboxes" do
    for key <- [:runtime, :sandbox, :tools, :subagents, :mcp_servers] do
      assert Application.get_env(:condukt, key) == nil, "global Condukt #{key} overrides the agent callbacks"
    end

    {:ok, modules} = :application.get_key(:atlas, :modules)

    agents =
      Enum.filter(modules, fn module ->
        Code.ensure_loaded?(module) and
          not String.starts_with?(Atom.to_string(module), "Elixir.Atlas.TestSupport.") and
          Condukt in List.flatten(Keyword.get_values(module.__info__(:attributes), :behaviour))
      end)

    assert ConversationAgent in agents
    assert DocumentClassifierAgent in agents

    coding_tool_names = Enum.map(Condukt.Tools.coding_tools(), &Tool.name/1)

    for agent <- [AnonymousAgent | agents] do
      assert agent.runtime() == Native, "#{inspect(agent)} needs an external runtime"
      assert agent.sandbox() in [nil, Local], "#{inspect(agent)} needs a remote sandbox"
      assert agent.mcp_servers() == [], "#{inspect(agent)} starts a separate MCP transport"
      assert_disjoint_tools(agent.tools(), coding_tool_names)

      for {_name, opts} <- agent.subagents() do
        assert Keyword.get(opts, :runtime) in [nil, Native]
        assert Keyword.get(opts, :sandbox) in [nil, Local]
        assert_disjoint_tools(Keyword.get(opts, :tools, []), coding_tool_names)
      end
    end
  end

  defp assert_disjoint_tools(tools, coding_tool_names) do
    for tool <- tools do
      refute tool == Command
      refute match?({Command, _opts}, tool)
      refute Tool.name(tool) in coding_tool_names
    end
  end

  describe "client_opts/1" do
    test "builds provider model specs from configured provider strings" do
      opts =
        Runner.client_opts(%{
          model: "openai:gpt-4.1",
          api_key: "api-key"
        })

      assert opts[:api_key] == "api-key"
      assert %{id: "gpt-4.1", provider: :openai} = opts[:model]
      assert opts[:retry] == false
    end

    test "raises a descriptive error for unsupported provider strings" do
      assert_raise ArgumentError, "unsupported LLM provider: unknown", fn ->
        Runner.client_opts(%{
          model: "unknown:some-model",
          api_key: "api-key"
        })
      end
    end

    test "includes a session timeout with buffer when ReqLLM receive timeout is configured" do
      opts =
        Runner.client_opts(%{
          model: "custom-model",
          api_key: "api-key",
          base_url: "https://llm.example",
          receive_timeout: :timer.minutes(5)
        })

      assert opts[:api_key] == "api-key"
      assert opts[:base_url] == "https://llm.example"
      assert opts[:model] == "custom-model"
      assert opts[:timeout] == :timer.minutes(5) + :timer.seconds(30)
    end

    test "omits timeout when ReqLLM receive timeout is not configured" do
      opts =
        Runner.client_opts(%{
          model: "custom-model",
          api_key: "api-key"
        })

      refute Keyword.has_key?(opts, :timeout)
    end

    test "local mode injects the LocalTransport plug and needs no model or api_key" do
      opts = Runner.client_opts(%{mode: :local})

      # The model id is a sentinel — LocalTransport rewrites it to the
      # default profile's name before the request reaches the controller.
      # Provider is fixed to :openai because Atlas.Inference speaks the
      # OpenAI-compatible surface.
      assert %{id: "atlas-default", provider: :openai} = opts[:model]
      assert opts[:api_key] == "local"
      assert opts[:retry] == false
      # The plug must live under `llm_request_options`: Condukt only threads
      # `req_http_options` through to ReqLLM when it arrives nested there. A
      # top-level `req_http_options` is silently dropped, which sends every
      # local-mode agent call to the sentinel host instead of the plug.
      assert opts[:llm_request_options] == [req_http_options: [plug: {LocalTransport, []}]]
      refute Keyword.has_key?(opts, :req_http_options)
      # Base URL is a sentinel that Req uses to construct a valid URL before
      # the plug intercepts. It should never leave the process.
      assert opts[:base_url] == "http://atlas-local"
    end
  end

  describe "local-mode plug threading through Condukt" do
    test "the ReqLLM request flows through the Plug carried in llm_request_options" do
      test_pid = self()

      opts =
        probe_opts(fn conn ->
          send(test_pid, {:probe_plug_called, conn.request_path})
          Req.Test.json(conn, completion(%{"role" => "assistant", "content" => "ok"}))
        end)

      assert {:ok, "ok"} = Condukt.run(AnonymousAgent, "ping", opts)
      assert_receive {:probe_plug_called, "/chat/completions"}, 2_000
    end

    test "local reply events execute the real model/tool loop through the Plug instead of Finch streaming" do
      test_pid = self()

      tool =
        Condukt.tool(
          name: "lookup_status",
          description: "Look up the current status",
          parameters: %{type: "object", properties: %{}},
          call: fn _params, _context ->
            send(test_pid, :tool_executed)
            {:ok, "healthy"}
          end
        )

      opts =
        probe_opts(fn conn ->
          assert conn.request_path == "/chat/completions"
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          request = JSON.decode!(body)
          refute request["stream"]

          response =
            if Enum.any?(request["messages"], &(&1["role"] == "tool")) do
              assert Enum.any?(request["messages"], &(&1["content"] == "healthy"))
              completion(%{"role" => "assistant", "content" => "Everything is healthy."})
            else
              completion(
                %{
                  "role" => "assistant",
                  "content" => nil,
                  "tool_calls" => [
                    %{
                      "id" => "call-status",
                      "type" => "function",
                      "function" => %{"name" => "lookup_status", "arguments" => "{}"}
                    }
                  ]
                },
                "tool_calls"
              )
            end

          Req.Test.json(conn, response)
        end)
        |> Keyword.put(:tools, [tool])

      assert [{:text, "Everything is healthy."}, :done] =
               Runner.with_reply_stream(%{mode: :local}, AnonymousAgent, "Check status", opts, &Enum.to_list/1)

      assert_receive :tool_executed
    end

    test "local reply events preserve provider failures" do
      opts =
        probe_opts(fn conn ->
          conn
          |> Plug.Conn.put_status(402)
          |> Req.Test.json(%{"error" => %{"message" => "Payment required"}})
        end)

      assert [{:error, %{status: 402}}] =
               Runner.with_reply_stream(%{mode: :local}, AnonymousAgent, "ping", opts, &Enum.to_list/1)
    end
  end

  defp probe_opts(plug) do
    %{mode: :local}
    |> Runner.client_opts()
    |> Keyword.put(:load_project_instructions, false)
    |> Keyword.put(:llm_request_options, req_http_options: [plug: plug])
  end

  defp completion(message, finish_reason \\ "stop") do
    %{
      "id" => "chatcmpl-test",
      "object" => "chat.completion",
      "created" => 0,
      "model" => "atlas-default",
      "choices" => [%{"index" => 0, "finish_reason" => finish_reason, "message" => message}],
      "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2}
    }
  end
end
