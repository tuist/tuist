defmodule Tuist.Accounts.AISubscriptions.InferenceTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.AISubscriptions.Inference
  alias Tuist.Accounts.User

  test "four maximal Luft images leave room for prompt history and tools" do
    image = "data:image/png;base64," <> Base.encode64(String.duplicate("x", 1_048_576))
    parts = List.duplicate(%{"type" => "image_url", "image_url" => %{"url" => image}}, 4)

    request =
      Map.put(params(), "messages", [
        %{"role" => "system", "content" => String.duplicate("p", 1_048_576)},
        %{"role" => "user", "content" => parts}
      ])

    assert :ok = Inference.validate_request(request)
    tool = hd(params()["tools"])
    assert :ok = Inference.validate_request(Map.put(request, "tools", List.duplicate(tool, 64)))

    assert {:error, 400, :invalid_request} =
             Inference.validate_request(Map.put(request, "tools", List.duplicate(tool, 65)))

    assert {:error, 400, :invalid_request} =
             Inference.validate_request(
               Map.put(request, "messages", [
                 %{"role" => "user", "content" => String.duplicate("x", 8_388_608)}
               ])
             )
  end

  test "bounded requests reject malformed nested messages and provider overrides" do
    assert :ok = Inference.validate_request(params())

    for invalid <- [
          %{},
          Map.put(params(), "model", "bad/model"),
          Map.put(params(), "stream", true),
          Map.put(params(), "base_url", "https://other.invalid"),
          Map.put(params(), "messages", List.duplicate(%{"role" => "user", "content" => "x"}, 257)),
          Map.put(params(), "messages", [%{"role" => "system", "content" => []}]),
          Map.put(params(), "messages", [%{"role" => "user", "content" => [%{"type" => "invalid"}]}]),
          Map.put(params(), "tools", [%{"type" => "function", "function" => nil}]),
          Map.put(params(), "messages", [%{"role" => "user", "content" => String.duplicate("x", 8_388_608)}])
        ] do
      assert {:error, 400, :invalid_request} = Inference.validate_request(invalid)
    end
  end

  test "Claude is refused without credential lookup or transport" do
    reject(AISubscriptions, :credentials, 2)
    reject(Req, :get, 1)
    reject(Req, :post, 1)

    assert {:error, 403, :unsupported_subscription} =
             Inference.personal_completion(%User{id: 1}, Map.put(params(), "provider", "claude"), fn -> true end)
  end

  test "rechecks authority after credential refresh before catalog dispatch" do
    stub(AISubscriptions, :credentials, fn _, :chatgpt -> {:ok, %{access_token: token()}} end)
    reject(Req, :get, 1)
    reject(Req, :post, 1)
    assert {:error, 403, :forbidden} = Inference.personal_completion(%User{id: 1}, params(), fn -> false end)
  end

  test "catalog projects compatible choices only and never provider instructions" do
    plug = fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> token()]
      Req.Test.json(conn, %{"models" => [model(), model(), Map.put(model(), "visibility", "hidden"), nil]})
    end

    assert {:ok, [%{provider: "chatgpt", id: "selected-model", name: "Selected"}]} =
             Inference.catalog(token(), plug: plug)
  end

  test "protocol adapter preserves text, tools, opaque reasoning and usage" do
    reasoning = %{"type" => "reasoning", "encrypted_content" => "opaque"}

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(body)
      assert request["model"] == "selected-model"
      assert request["store"] == false
      assert request["reasoning"] == %{"effort" => "low"}
      assert request["instructions"] == "Private instructions"
      assert [%{"name" => "read", "type" => "function", "strict" => false}] = request["tools"]

      sse(conn, [
        %{
          "type" => "response.completed",
          "response" => %{
            "id" => "reply",
            "model" => "selected-model",
            "status" => "completed",
            "output" => [
              reasoning,
              %{"type" => "message", "content" => [%{"type" => "output_text", "text" => "Done"}]},
              %{"type" => "function_call", "call_id" => "call", "name" => "read", "arguments" => "{}"}
            ],
            "usage" => %{"input_tokens" => 12, "output_tokens" => 3}
          }
        }
      ])
    end

    assert {:ok, completion} = Inference.complete(:chatgpt, token(), params(), plug: plug)
    assert completion["usage"] == %{"prompt_tokens" => 12, "completion_tokens" => 3}
    assert [%{"message" => message, "finish_reason" => "tool_calls"}] = completion["choices"]
    assert message["content"] == "Done"
    assert message["reasoning_details"] == [%{"format" => "tuist-codex-v1", "item" => reasoning}]
    assert [%{"id" => "call", "function" => %{"name" => "read", "arguments" => "{}"}}] = message["tool_calls"]
    refute JSON.encode!(completion) =~ token()
  end

  test "incomplete streams and upstream errors are private-data-free categories" do
    assert {:error, 502, :incomplete_stream} =
             Inference.complete(:chatgpt, token(), params(),
               plug: &sse(&1, [%{"type" => "response.output_item.done", "item" => %{"type" => "reasoning"}}])
             )

    for {code, status, category} <- [
          {"rate_limit_exceeded", 429, :rate_limited},
          {"context_length_exceeded", 400, :context_length},
          {"unknown-secret", 502, :upstream_error}
        ] do
      assert {:error, ^status, ^category} =
               Inference.complete(:chatgpt, token(), params(),
                 plug: &sse(&1, [%{"type" => "error", "error" => %{"code" => code, "message" => token()}}])
               )
    end

    assert {:error, 401, :invalid_account_claim} = Inference.complete(:chatgpt, "invalid", params())

    assert {:error, 504, :timeout} =
             Inference.complete(:chatgpt, token(), params(), plug: &Req.Test.transport_error(&1, :timeout))
  end

  defp params do
    %{
      "model" => "selected-model",
      "messages" => [
        %{"role" => "system", "content" => "Private instructions"},
        %{"role" => "user", "content" => "Inspect"}
      ],
      "tools" => [%{"type" => "function", "function" => %{"name" => "read"}}]
    }
  end

  defp model do
    %{
      "slug" => "selected-model",
      "display_name" => "Selected",
      "visibility" => "list",
      "instructions" => "private",
      "supported_reasoning_levels" => [%{"effort" => "low"}]
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
