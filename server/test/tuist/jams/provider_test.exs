defmodule Tuist.Jams.ProviderTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.User
  alias Tuist.Jams.Agent
  alias Tuist.Jams.ModelFence
  alias Tuist.Jams.Provider

  test "ChatGPT preserves selected model, tools, results and opaque reasoning" do
    reasoning = %{"type" => "reasoning", "encrypted_content" => "opaque-state"}
    params = params()

    params =
      update_in(
        params["messages"],
        &(&1 ++
            [
              %{
                "role" => "assistant",
                "content" => nil,
                "reasoning_details" => [%{"format" => "tuist-codex-v1", "item" => reasoning}],
                "tool_calls" => [%{"id" => "call-1", "function" => %{"name" => "read", "arguments" => "{}"}}]
              },
              %{"role" => "tool", "tool_call_id" => "call-1", "content" => "source"}
            ])
      )

    plug = fn conn ->
      assert conn.host == "chatgpt.com"
      assert conn.request_path == "/backend-api/codex/responses"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> token()]
      assert Plug.Conn.get_req_header(conn, "chatgpt-account-id") == ["personal-account"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = JSON.decode!(body)
      assert body["model"] == "selected-model"
      assert body["instructions"] == "Jam instructions"
      assert body["store"] == false
      assert body["stream"] == true
      assert body["reasoning"] == %{"effort" => "low"}
      assert body["include"] == ["reasoning.encrypted_content"]
      refute Map.has_key?(body, "max_tokens")
      assert reasoning in body["input"]
      assert %{"type" => "function_call_output", "call_id" => "call-1", "output" => "source"} in body["input"]
      assert [%{"name" => "read", "type" => "function", "strict" => false}] = body["tools"]

      sse(conn, [
        %{"type" => "response.output_item.done", "item" => reasoning},
        %{
          "type" => "response.output_item.done",
          "item" => %{
            "type" => "function_call",
            "call_id" => "call-2",
            "name" => "read",
            "arguments" => ~s({"path":"mix.exs"})
          }
        },
        %{"type" => "response.completed", "response" => %{"id" => "response-1", "model" => "selected-model"}}
      ])
    end

    assert {:ok, %{"choices" => [%{"message" => message, "finish_reason" => "tool_calls"}]}} =
             Provider.complete(:chatgpt, token(), params, plug: plug)

    assert [%{"id" => "call-2", "function" => %{"name" => "read", "arguments" => ~s({"path":"mix.exs"})}}] =
             message["tool_calls"]

    assert [%{"format" => "tuist-codex-v1", "item" => ^reasoning}] = message["reasoning_details"]
  end

  test "Codex never accepts done items without a successful terminal event" do
    for terminal <- [
          nil,
          %{"type" => "response.incomplete"},
          %{"type" => "response.completed", "response" => %{"status" => "failed"}}
        ] do
      events = [
        %{
          "type" => "response.output_item.done",
          "item" => %{"type" => "function_call", "name" => "write", "arguments" => "{}"}
        }
      ]

      events = if terminal, do: events ++ [terminal], else: events
      assert {:error, 502, _} = Provider.complete(:chatgpt, token(), params(), plug: &sse(&1, events))
    end
  end

  test "Codex errors use only structured categories and never echo upstream text" do
    for {error, expected} <- [
          {%{"code" => "rate_limit_exceeded"}, {:error, 429, :rate_limited}},
          {%{"code" => "insufficient_quota"}, {:error, 402, :billing}},
          {%{"code" => "context_length_exceeded"}, {:error, 400, :context_length}},
          {%{"message" => "secret rate_limit_exceeded"}, {:error, 502, :upstream_error}}
        ] do
      assert Provider.complete(:chatgpt, token(), params(),
               plug: &sse(&1, [%{"type" => "response.failed", "response" => %{"error" => error}}])
             ) == expected
    end
  end

  test "Codex accepts complete terminal output and preserves text and usage" do
    assert {:ok,
            %{
              "choices" => [%{"message" => %{"content" => "Done"}, "finish_reason" => "stop"}],
              "usage" => %{"prompt_tokens" => 12, "completion_tokens" => 3}
            }} =
             Provider.complete(:chatgpt, token(), params(), plug: &sse(&1, completed()))
  end

  test "invalid ChatGPT account claims fail before HTTP" do
    assert {:error, 401, :invalid_account_claim} =
             Provider.complete(:chatgpt, "invalid", params(), plug: fn _ -> flunk("unexpected HTTP") end)
  end

  test "unsupported Claude subscriptions fail without impersonating Claude Code or making HTTP requests" do
    assert {:error, 403, :unsupported_subscription} =
             Provider.complete(:claude, "fixture-only", params(), plug: fn _ -> flunk("unexpected HTTP") end)

    user = %User{id: 7}
    stub(AISubscriptions, :list, fn ^user -> [%{provider: :claude, connected: true}] end)
    reject(AISubscriptions, :credentials, 2)
    assert %{models: [], errors: [%{provider: "claude", code: "unsupported_subscription"}]} = Provider.models(user)
    assert {:error, :not_connected} = Provider.client_opts(user, %{provider: "claude", model: "some-model"})
  end

  test "catalog uses subscription auth and projects only listed compatible models" do
    model = %{
      "slug" => "chosen-model",
      "display_name" => "Chosen",
      "visibility" => "list",
      "supported_reasoning_levels" => [%{"effort" => "low"}],
      "instructions" => "must not escape"
    }

    plug = fn conn ->
      assert conn.request_path == "/backend-api/codex/models"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> token()]
      assert Plug.Conn.get_req_header(conn, "chatgpt-account-id") == ["personal-account"]

      Req.Test.json(conn, %{
        models: [
          model,
          model,
          Map.put(model, "slug", "invalid/id"),
          Map.put(model, "visibility", "hidden"),
          Map.put(model, "supported_reasoning_levels", [%{effort: "high"}]),
          nil
        ]
      })
    end

    assert {:ok, [%{provider: "chatgpt", id: "chosen-model", name: "Chosen"}]} = Provider.catalog(token(), plug: plug)

    assert {:error, :models_unavailable} =
             Provider.catalog(token(), plug: &Plug.Conn.send_resp(&1, 401, "private failure"))
  end

  test "model validation is owner-scoped and rejects unlisted choices" do
    user = %User{id: 123}
    expect(AISubscriptions, :list, 2, fn ^user -> [%{provider: :chatgpt, connected: true}] end)
    expect(AISubscriptions, :credentials, 2, fn ^user, :chatgpt -> {:ok, %{access_token: token()}} end)

    expect(Req, :get, 2, fn opts ->
      assert {"authorization", "Bearer " <> token()} in opts[:headers]

      {:ok,
       %{
         status: 200,
         body: %{
           "models" => [
             %{
               "slug" => "allowed",
               "display_name" => "Allowed",
               "visibility" => "list",
               "supported_reasoning_levels" => [%{"effort" => "low"}]
             }
           ]
         }
       }}
    end)

    assert :ok = Provider.validate_model(user, "chatgpt", "allowed")
    assert {:error, :model_unavailable} = Provider.validate_model(user, "chatgpt", "other")
    assert {:error, :model_unavailable} = Provider.validate_model(user, "chatgpt", nil)
  end

  test "upstream HTTP errors and redirects are sanitized and not followed" do
    for status <- [302, 400, 401, 402, 403, 429, 503] do
      plug = fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://should-not-be-followed.invalid")
        |> Plug.Conn.send_resp(status, "private error body")
      end

      assert Provider.complete(:chatgpt, token(), params(), plug: plug) == {:error, status, :http_error}
    end

    assert {:error, 504, :timeout} =
             Provider.complete(:chatgpt, token(), params(), plug: &Req.Test.transport_error(&1, :timeout))
  end

  test "subscription requests work through the real Req and Finch transport" do
    server =
      start_supervised!(
        {Bandit, plug: fn conn, _ -> sse(conn, completed()) end, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    transport = fn request, finch_request, finch, opts ->
      assert {:ok, response} = Finch.request(%{finch_request | scheme: :http, host: "127.0.0.1", port: port}, finch, opts)
      {request, Req.Response.new(response)}
    end

    assert {:ok, %{"choices" => [%{"message" => %{"content" => "Done"}}]}} =
             Provider.complete(:chatgpt, token(), params(), finch_request: transport)
  end

  test "the transport fails closed without a run fence" do
    conn = Plug.Test.conn(:post, "/chat/completions", JSON.encode!(params()))
    refute ModelFence.authorized?(conn)
    assert %{status: 409, resp_body: body} = Provider.call(conn, user_id: 1, model: "chosen")
    assert %{"error" => %{"code" => "fenced"}} = JSON.decode!(body)
  end

  test "reply parsing retains legacy answers and bounds suggested messages" do
    assert Agent.decode_reply("plain answer") == {"plain answer", []}

    assert Agent.decode_reply(~s({"reply":" Done ","suggestions":[" Next? ","Next?",null,"","Two","Three","Four"]})) ==
             {"Done", ["Next?", "Two", "Three"]}

    assert Agent.decode_reply(
             JSON.encode!(%{reply: "Done", suggestions: [String.duplicate("界", 121), String.duplicate("界", 120)]})
           ) == {"Done", [String.duplicate("界", 120)]}

    assert Agent.decode_reply(~s(```json\n{"reply":"Done","suggestions":[]}\n```)) == {"Done", []}
  end

  defp completed do
    [
      %{
        "type" => "response.completed",
        "response" => %{
          "id" => "response-1",
          "model" => "selected-model",
          "status" => "completed",
          "output" => [%{"type" => "message", "content" => [%{"type" => "output_text", "text" => "Done"}]}],
          "usage" => %{"input_tokens" => 12, "output_tokens" => 3}
        }
      }
    ]
  end

  defp params do
    %{
      "model" => "selected-model",
      "messages" => [
        %{"role" => "system", "content" => "Jam instructions"},
        %{"role" => "user", "content" => "Inspect"}
      ],
      "tools" => [%{"type" => "function", "function" => %{"name" => "read"}}]
    }
  end

  defp token do
    claims = JSON.encode!(%{"https://api.openai.com/auth" => %{"chatgpt_account_id" => "personal-account"}})
    "header." <> Base.url_encode64(claims, padding: false) <> ".signature"
  end

  defp sse(conn, events) do
    body = Enum.map_join(events, "", &("data: " <> JSON.encode!(&1) <> "\r\n\r\n"))
    conn |> Plug.Conn.put_resp_content_type("text/event-stream") |> Plug.Conn.send_resp(200, body)
  end
end
