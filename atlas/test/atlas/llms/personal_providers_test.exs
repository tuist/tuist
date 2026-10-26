defmodule Atlas.LLMs.PersonalProvidersTest do
  use Atlas.DataCase, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Atlas.LLMs.PersonalProviders
  alias Condukt.AnonymousAgent
  alias Ecto.Adapters.SQL.Sandbox

  test "ChatGPT uses the subscription Responses endpoint and retains complete tool calls" do
    expect(Req, :post, fn opts ->
      assert opts[:url] == "https://chatgpt.com/backend-api/codex/responses"
      assert {"authorization", "Bearer " <> chatgpt_token()} in opts[:headers]
      assert {"chatgpt-account-id", "personal-account"} in opts[:headers]
      assert opts[:retry] == false and opts[:redirect] == false
      assert opts[:json]["reasoning"] == %{"effort" => "none"}
      assert opts[:json]["store"] == false
      assert opts[:json]["stream"] == true
      refute Map.has_key?(opts[:json], "max_tokens")
      assert opts[:json]["instructions"] == "Bounded Orbit instructions"
      assert Enum.any?(opts[:json]["input"], &(&1["type"] == "function_call_output"))
      assert Enum.any?(opts[:json]["input"], &(&1["type"] == "function_call" and &1["call_id"] == "call-1"))
      assert [%{"type" => "function", "name" => "list_accounts"}] = opts[:json]["tools"]

      response = %{
        "status" => "completed",
        "id" => "response-1",
        "model" => "gpt-5.4",
        "output" => [
          %{"type" => "function_call", "call_id" => "call-2", "name" => "list_accounts", "arguments" => "{}"}
        ]
      }

      {:ok,
       %{
         status: 200,
         body:
           "event: response.completed\ndata: " <>
             JSON.encode!(%{type: "response.completed", response: response}) <> "\n\n"
       }}
    end)

    assert {:ok, %{"choices" => [%{"message" => message, "finish_reason" => "tool_calls"}]}} =
             PersonalProviders.complete("chatgpt", chatgpt_token(), params())

    assert [%{"id" => "call-2", "function" => %{"name" => "list_accounts", "arguments" => "{}"}}] =
             message["tool_calls"]
  end

  test "Claude uses bearer subscription auth and preserves tools, tool results and image bytes" do
    expect(Req, :post, fn opts ->
      assert opts[:url] == "https://api.anthropic.com/v1/messages"
      assert {"authorization", "Bearer setup-token"} in opts[:headers]
      refute Enum.any?(opts[:headers], fn {name, _} -> name == "x-api-key" end)
      assert opts[:json]["system"] |> Enum.any?(&(&1["text"] == "Bounded Orbit instructions"))
      assert [%{"name" => "list_accounts", "input_schema" => %{}}] = opts[:json]["tools"]

      assert Enum.any?(opts[:json]["messages"], fn message ->
               Enum.any?(message["content"], &(&1["type"] == "tool_result" and &1["tool_use_id"] == "call-1"))
             end)

      assert Enum.any?(opts[:json]["messages"], fn message ->
               Enum.any?(message["content"], &(&1["type"] == "image" and &1["source"]["data"] == "aW1hZ2U="))
             end)

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => "message-1",
           "model" => "claude-sonnet-4-6",
           "content" => [
             %{"type" => "text", "text" => "Found it"},
             %{"type" => "tool_use", "id" => "call-2", "name" => "list_accounts", "input" => %{"query" => "Example"}}
           ]
         }
       }}
    end)

    assert {:ok, %{"choices" => [%{"message" => message}]}} =
             PersonalProviders.complete("claude", "setup-token", params())

    assert message["content"] == "Found it"
    assert [%{"function" => %{"arguments" => args}}] = message["tool_calls"]
    assert JSON.decode!(args) == %{"query" => "Example"}
  end

  test "the real Req transport is bounded and never sends credentials through Atlas's named Finch pool" do
    expect(Finch, :stream_while, fn request, pool, acc, callback, opts ->
      assert request.host == "api.anthropic.com"
      assert request.path == "/v1/messages"
      refute pool == Atlas.Finch
      assert opts[:receive_timeout] == 45_000

      events = [
        {:status, 200},
        {:headers, [{"content-type", "application/json"}]},
        {:data, JSON.encode!(%{id: "message-1", model: "claude-sonnet-4-6", content: [%{type: "text", text: "Ready"}]})}
      ]

      {:ok,
       Enum.reduce(events, acc, fn event, acc ->
         {:cont, acc} = callback.(event, acc)
         acc
       end)}
    end)

    assert {:ok, %{"choices" => [%{"message" => %{"content" => "Ready"}}]}} =
             PersonalProviders.complete("claude", "setup-token", params())
  end

  test "errors and incomplete streams never expose provider bodies or accept a partial reply" do
    for provider <- ["chatgpt", "claude"], status <- [400, 401, 402, 403, 429, 503] do
      expect(Req, :post, fn _opts -> {:ok, %{status: status, body: "secret provider payload"}} end)

      log =
        capture_log([level: :error], fn ->
          assert {:error, ^status} = PersonalProviders.complete(provider, chatgpt_token(), params())
        end)

      assert log =~ "Orbit personal provider failed: provider=#{provider} category=http_error status=#{status}"
      refute log =~ "secret provider payload"
      refute log =~ chatgpt_token()
    end

    expect(Req, :post, fn _opts ->
      {:ok, %{status: 200, body: ~s(data: {"type":"response.output_text.delta","delta":"partial"}\n\n)}}
    end)

    assert {:error, 502} = PersonalProviders.complete("chatgpt", chatgpt_token(), params())
    assert {:error, 401} = PersonalProviders.complete("chatgpt", "invalid-token", params())
  end

  test "nonempty reasoning is rejected rather than lost before the next tool turn" do
    for state <- [
          %{"encrypted_content" => "opaque-provider-state", "summary" => []},
          %{"summary" => [%{"type" => "summary_text", "text" => "private reasoning"}]},
          %{"content" => [%{"type" => "reasoning_text", "text" => "private reasoning"}]}
        ],
        terminal <- [:full, :metadata_only] do
      expect(Req, :post, fn opts ->
        assert opts[:json]["reasoning"] == %{"effort" => "none"}

        response = %{
          "status" => "completed",
          "output" => [
            Map.put(state, "type", "reasoning"),
            %{"type" => "function_call", "call_id" => "call-2", "name" => "list_accounts", "arguments" => "{}"}
          ]
        }

        done = Enum.map(response["output"], &%{"type" => "response.output_item.done", "item" => &1})
        response = if terminal == :full, do: response, else: %{"id" => "resp_reasoning"}
        {:ok, %{status: 200, body: sse(done ++ [%{"type" => "response.completed", "response" => response}])}}
      end)

      log =
        capture_log(fn -> assert {:error, 502} = PersonalProviders.complete("chatgpt", chatgpt_token(), params()) end)

      assert log =~ "category=unsupported_reasoning"
      refute log =~ "opaque-provider-state"
      refute log =~ "private reasoning"
    end
  end

  test "a real Req timeout retains its sanitized gateway-timeout status" do
    expect(Finch, :stream_while, fn _request, _pool, acc, _callback, _opts ->
      {:error, %Mint.TransportError{reason: :timeout}, acc}
    end)

    log =
      capture_log([level: :error], fn ->
        assert {:error, 504} = PersonalProviders.complete("claude", "setup-token", params())
      end)

    assert log =~ "Orbit personal provider failed: provider=claude category=timeout status=504"
    refute log =~ "setup-token"
    refute log =~ "Mint.TransportError"
  end

  for {provider, terminal} <- [{"chatgpt", :full}, {"chatgpt", :metadata_only}, {"claude", :full}] do
    @tag provider: provider, terminal: terminal
    test "#{provider} (#{terminal}): real Condukt and ReqLLM round-trip parallel tools through the subscription adapter",
         %{
           provider: provider,
           terminal: terminal
         } do
      owner = self()

      expect(Finch, :stream_while, 2, fn request, _pool, acc, callback, _opts ->
        body = request.body |> IO.iodata_to_binary() |> JSON.decode!()
        assert body["model"] in ["gpt-5.4", "claude-sonnet-4-6"]

        tools = body["tools"]
        assert [%{"name" => "lookup_status"} = tool] = tools
        schema = tool[if(provider == "chatgpt", do: "parameters", else: "input_schema")]
        assert schema["properties"]["kind"]["type"] == "string"

        continuing? = tool_continuation?(provider, body)

        if continuing? do
          send(owner, :continued_after_both_tools)
          assert_tool_continuation(provider, body)
        else
          assert_initial_request(provider, body)
        end

        {content_type, response} = provider_fixture(provider, continuing?, terminal)
        # Exercise Req's SSE buffering with network frames split inside JSON.
        midpoint = div(byte_size(response), 2)
        first = binary_part(response, 0, midpoint)
        second = binary_part(response, midpoint, byte_size(response) - midpoint)

        events = [
          {:status, 200},
          {:headers, [{"content-type", content_type}]},
          {:data, first},
          {:data, second}
        ]

        {:ok,
         Enum.reduce(events, acc, fn event, acc ->
           {:cont, acc} = callback.(event, acc)
           acc
         end)}
      end)

      plug = fn conn ->
        allow(Finch, owner, self())
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = JSON.decode!(body)

        case PersonalProviders.complete(provider, chatgpt_token(), params) do
          {:ok, completion} ->
            Req.Test.json(conn, completion)

          {:error, status} ->
            conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{"error" => %{"code" => "provider_error"}})
        end
      end

      tool =
        Condukt.tool(
          name: "lookup_status",
          description: "Read the current status",
          parameters: %{type: "object", properties: %{kind: %{type: "string"}}, required: ["kind"]},
          call: fn %{"kind" => kind}, _context ->
            send(owner, {:tool_executed, kind})
            {:ok, "#{kind} evidence"}
          end
        )

      opts = [
        model: ReqLLM.model!(%{id: "atlas-orbit", provider: :openai}),
        api_key: "local",
        base_url: "http://atlas-local",
        system_prompt: "Bounded Orbit instructions",
        load_project_instructions: false,
        llm_request_options: [req_http_options: [plug: plug]],
        retry: false,
        timeout: 5_000,
        tools: [tool]
      ]

      agent = start_supervised!({AnonymousAgent, opts})
      Sandbox.allow(Repo, owner, agent)

      assert {:ok, "Both lookups completed."} = Condukt.run(agent, "What needs my attention?", timeout: 5_000)
      assert_receive {:tool_executed, "tasks"}
      assert_receive {:tool_executed, "invoices"}
      assert_receive :continued_after_both_tools
    end
  end

  test "HTTP-200 SSE terminal failures preserve only fixed structured categories" do
    for {error, status, category} <- [
          {%{"code" => "rate_limit_exceeded"}, 429, "rate_limited"},
          {%{"code" => "insufficient_quota"}, 402, "billing"},
          {%{"code" => "context_length_exceeded"}, 400, "invalid_request"},
          {%{"code" => "invalid_prompt"}, 400, "invalid_request"},
          {%{"type" => "invalid_request_error", "code" => nil}, 400, "invalid_request"},
          {%{"type" => "usage_limit_reached"}, 429, "rate_limited"},
          {%{"code" => "server_error"}, 502, "upstream_error"},
          {%{"code" => "private-unknown-code"}, 502, "upstream_error"}
        ],
        type <- ["response.failed", "error", "nested_error"],
        not (type == "error" and is_map_key(error, "type")) do
      error = Map.put(error, "message", "private body with token and prompt: invalid api key")

      event =
        case type do
          "response.failed" ->
            %{"type" => type, "response" => %{"id" => "resp_failed", "status" => "failed", "error" => error}}

          "error" ->
            Map.put(error, "type", "error")

          "nested_error" ->
            %{"type" => "error", "error" => error}
        end

      expect(Finch, :stream_while, fn _request, _pool, acc, callback, _opts ->
        events = [{:status, 200}, {:headers, [{"content-type", "text/event-stream"}]}, {:data, sse([event])}]

        {:ok,
         Enum.reduce(events, acc, fn event, acc ->
           {:cont, acc} = callback.(event, acc)
           acc
         end)}
      end)

      log =
        capture_log([level: :error], fn ->
          assert {:error, ^status} = PersonalProviders.complete("chatgpt", chatgpt_token(), params())
        end)

      assert log =~ "provider=chatgpt"
      assert log =~ "category=#{category}"
      refute log =~ "private"
      refute log =~ chatgpt_token()
    end
  end

  test "SSE incomplete and malformed terminal events never accept text deltas as a complete answer" do
    for {event, category} <- [
          {%{
             "type" => "response.incomplete",
             "response" => %{"status" => "incomplete", "incomplete_details" => %{"reason" => "max_output_tokens"}}
           }, "incomplete_response"},
          {%{"type" => "response.failed", "response" => nil}, "invalid_response"},
          {%{"type" => "response.completed", "response" => %{"id" => "resp_without_items"}}, "invalid_response"},
          {%{"type" => "response.completed", "response" => %{"status" => "completed", "output" => nil}},
           "invalid_response"}
        ] do
      partial = %{"type" => "response.output_text.delta", "delta" => "private partial text"}
      expect(Req, :post, fn _opts -> {:ok, %{status: 200, body: sse([partial, event])}} end)

      log =
        capture_log(fn -> assert {:error, 502} = PersonalProviders.complete("chatgpt", chatgpt_token(), params()) end)

      assert log =~ "category=#{category}"
      refute log =~ "private partial text"
    end
  end

  test "complete SSE tool items cannot execute without a successful terminal event" do
    done = %{
      "type" => "response.output_item.done",
      "item" => %{"type" => "function_call", "call_id" => "call_tasks", "name" => "lookup_status", "arguments" => "{}"}
    }

    for terminal <- [
          [],
          [%{"type" => "response.incomplete", "response" => %{"status" => "incomplete"}}],
          [%{"type" => "response.failed", "response" => %{"error" => %{"code" => "server_error"}}}],
          [%{"type" => "response.completed", "response" => %{"status" => "in_progress"}}]
        ] do
      expect(Req, :post, fn _opts -> {:ok, %{status: 200, body: sse([done | terminal])}} end)
      assert {:error, 502} = PersonalProviders.complete("chatgpt", chatgpt_token(), params())
    end
  end

  test "Claude token-limit responses cannot execute a truncated tool call as a successful turn" do
    expect(Req, :post, fn _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => "msg_truncated",
           "model" => "claude-sonnet-4-6",
           "stop_reason" => "max_tokens",
           "content" => [%{"type" => "tool_use", "id" => "toolu_partial", "name" => "lookup_status", "input" => %{}}]
         }
       }}
    end)

    assert {:error, 502} = PersonalProviders.complete("claude", "setup-token", params())
  end

  defp assert_initial_request("chatgpt", body) do
    assert body["reasoning"] == %{"effort" => "none"}
    assert body["instructions"] == "Bounded Orbit instructions"
    assert body["store"] == false
    assert body["stream"] == true
    assert [%{"role" => "user", "content" => "What needs my attention?"}] = body["input"]
  end

  defp assert_initial_request("claude", body) do
    assert Enum.any?(body["system"], &(&1["text"] == "Bounded Orbit instructions"))

    assert [%{"role" => "user", "content" => [%{"type" => "text", "text" => "What needs my attention?"}]}] =
             body["messages"]
  end

  defp tool_continuation?("chatgpt", body), do: Enum.any?(body["input"], &(&1["type"] == "function_call_output"))

  defp tool_continuation?("claude", body) do
    Enum.any?(body["messages"], fn message -> Enum.any?(message["content"], &(&1["type"] == "tool_result")) end)
  end

  defp assert_tool_continuation("chatgpt", body) do
    calls = Enum.filter(body["input"], &(&1["type"] == "function_call"))
    results = Enum.filter(body["input"], &(&1["type"] == "function_call_output"))
    assert Enum.map(calls, & &1["call_id"]) == ["call_tasks", "call_invoices"]
    assert Enum.map(calls, &JSON.decode!(&1["arguments"])) == [%{"kind" => "tasks"}, %{"kind" => "invoices"}]

    assert Enum.map(results, &{&1["call_id"], &1["output"]}) == [
             {"call_tasks", "tasks evidence"},
             {"call_invoices", "invoices evidence"}
           ]

    refute Enum.any?(body["input"], &(&1["type"] == "reasoning"))
  end

  defp assert_tool_continuation("claude", body) do
    [assistant] = Enum.filter(body["messages"], &(&1["role"] == "assistant"))
    calls = Enum.filter(assistant["content"], &(&1["type"] == "tool_use"))
    results = for message <- body["messages"], part <- message["content"], part["type"] == "tool_result", do: part
    assert Enum.map(calls, & &1["id"]) == ["call_tasks", "call_invoices"]
    assert Enum.map(calls, & &1["input"]) == [%{"kind" => "tasks"}, %{"kind" => "invoices"}]

    assert Enum.map(results, &{&1["tool_use_id"], &1["content"]}) == [
             {"call_tasks", "tasks evidence"},
             {"call_invoices", "invoices evidence"}
           ]
  end

  # Synthetic protocol fixtures, not captured provider responses or proof of account eligibility.
  # Shapes: OpenAI Responses stream events and Anthropic Messages tool-use responses.
  defp provider_fixture("chatgpt", continuing?, terminal) do
    output =
      if continuing? do
        [
          %{
            "type" => "message",
            "id" => "msg_final",
            "role" => "assistant",
            "status" => "completed",
            "content" => [%{"type" => "output_text", "text" => "Both lookups completed.", "annotations" => []}]
          }
        ]
      else
        [%{"type" => "reasoning", "id" => "rs_empty", "summary" => []}] ++
          Enum.map(["tasks", "invoices"], fn kind ->
            %{
              "type" => "function_call",
              "id" => "fc_#{kind}",
              "call_id" => "call_#{kind}",
              "status" => "completed",
              "name" => "lookup_status",
              "arguments" => JSON.encode!(%{kind: kind})
            }
          end)
      end

    response = %{
      "id" => "resp_fixture",
      "object" => "response",
      "status" => "completed",
      "error" => nil,
      "incomplete_details" => nil,
      "model" => "gpt-5.4",
      "output" => output,
      "usage" => %{"input_tokens" => 90, "output_tokens" => 30, "total_tokens" => 120}
    }

    # Codex's own stream tests complete with only id/end_turn; complete items
    # arrive separately in output_item.done, not necessarily terminal.output.
    done = Enum.map(output, &%{"type" => "response.output_item.done", "item" => &1})

    terminal_response =
      if terminal == :full,
        do: response,
        else: response |> Map.take(["id", "usage"]) |> Map.put("end_turn", continuing?)

    events =
      [
        %{
          "type" => "response.created",
          "sequence_number" => 0,
          "response" => %{response | "status" => "in_progress", "output" => []}
        }
      ] ++ done ++ [%{"type" => "response.completed", "response" => terminal_response}]

    {"text/event-stream", sse(events)}
  end

  defp provider_fixture("claude", continuing?, _terminal) do
    content =
      if continuing? do
        [%{"type" => "text", "text" => "Both lookups completed."}]
      else
        Enum.map(["tasks", "invoices"], fn kind ->
          %{"type" => "tool_use", "id" => "call_#{kind}", "name" => "lookup_status", "input" => %{"kind" => kind}}
        end)
      end

    {"application/json",
     JSON.encode!(%{
       "id" => "msg_fixture",
       "type" => "message",
       "role" => "assistant",
       "model" => "claude-sonnet-4-6",
       "content" => content,
       "stop_reason" => if(continuing?, do: "end_turn", else: "tool_use"),
       "stop_sequence" => nil,
       "usage" => %{"input_tokens" => 90, "output_tokens" => 30}
     })}
  end

  defp sse(events), do: Enum.map_join(events, "", &"event: #{&1["type"]}\ndata: #{JSON.encode!(&1)}\n\n")

  defp chatgpt_token do
    claims = %{"https://api.openai.com/auth" => %{"chatgpt_account_id" => "personal-account"}}
    "header." <> Base.url_encode64(JSON.encode!(claims), padding: false) <> ".signature"
  end

  defp params do
    %{
      "messages" => [
        %{"role" => "system", "content" => "Bounded Orbit instructions"},
        %{
          "role" => "user",
          "content" => [%{"type" => "image_url", "image_url" => %{"url" => "data:image/png;base64,aW1hZ2U="}}]
        },
        %{
          "role" => "assistant",
          "content" => nil,
          "tool_calls" => [%{"id" => "call-1", "function" => %{"name" => "list_accounts", "arguments" => "{}"}}]
        },
        %{"role" => "tool", "tool_call_id" => "call-1", "content" => "Account evidence"}
      ],
      "tools" => [
        %{
          "type" => "function",
          "function" => %{"name" => "list_accounts", "description" => "Read accounts", "parameters" => %{}}
        }
      ]
    }
  end
end
