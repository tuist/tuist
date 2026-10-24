defmodule Atlas.LLMs.PersonalProvidersTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.LLMs.PersonalProviders

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
      assert {:error, ^status} = PersonalProviders.complete(provider, chatgpt_token(), params())
    end

    expect(Req, :post, fn _opts ->
      {:ok, %{status: 200, body: ~s(data: {"type":"response.output_text.delta","delta":"partial"}\n\n)}}
    end)

    assert {:error, 502} = PersonalProviders.complete("chatgpt", chatgpt_token(), params())
    assert {:error, 401} = PersonalProviders.complete("chatgpt", "invalid-token", params())
  end

  test "unexpected opaque reasoning is rejected rather than lost before the next tool turn" do
    expect(Req, :post, fn opts ->
      assert opts[:json]["reasoning"] == %{"effort" => "none"}

      response = %{
        "status" => "completed",
        "output" => [
          %{"type" => "reasoning", "encrypted_content" => "opaque-provider-state"},
          %{"type" => "function_call", "call_id" => "call-2", "name" => "list_accounts", "arguments" => "{}"}
        ]
      }

      {:ok, %{status: 200, body: "data: " <> JSON.encode!(%{type: "response.completed", response: response}) <> "\n\n"}}
    end)

    assert {:error, 502} = PersonalProviders.complete("chatgpt", chatgpt_token(), params())
  end

  test "a real Req timeout retains its sanitized gateway-timeout status" do
    expect(Finch, :stream_while, fn _request, _pool, acc, _callback, _opts ->
      {:error, %Mint.TransportError{reason: :timeout}, acc}
    end)

    assert {:error, 504} = PersonalProviders.complete("claude", "setup-token", params())
  end

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
