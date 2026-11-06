defmodule Atlas.InferenceTest do
  use ExUnit.Case, async: true

  alias Atlas.Inference
  alias Atlas.Inference.ModelBinding

  describe "relay_request/3 reasoning controls" do
    setup tags do
      Atlas.DataCase.setup_sandbox(tags)

      provider = %{base_url: "https://provider.example", api_key: "test"}
      %{config: [providers: %{"together" => provider, "openai" => provider}]}
    end

    test "disables Together reasoning when an alias caller requests no reasoning", %{config: config} do
      binding = %ModelBinding{name: "Translator", upstream_provider: "together", upstream_model: "Qwen/Qwen3.7-Plus"}

      for streamed? <- [false, true] do
        body = %{
          "model" => "Translator",
          "messages" => [%{"role" => "user", "content" => "Translate this."}],
          "reasoning_effort" => "none",
          "max_tokens" => 32_768,
          "stream" => streamed?
        }

        assert {:ok, request} = Inference.relay_request(binding, body, config: config)

        assert request[:json] == %{
                 "model" => "Qwen/Qwen3.7-Plus",
                 "messages" => [%{"role" => "user", "content" => "Translate this."}],
                 "reasoning" => %{"enabled" => false},
                 "max_tokens" => 32_768,
                 "stream" => streamed?
               }
      end
    end

    test "preserves an explicit Together reasoning setting", %{config: config} do
      binding = %ModelBinding{name: "Translator", upstream_provider: "together", upstream_model: "Qwen/Qwen3.7-Plus"}
      body = %{"reasoning_effort" => "none", "reasoning" => %{"enabled" => true}}

      assert {:ok, request} = Inference.relay_request(binding, body, config: config)
      assert request[:json]["reasoning"] == %{"enabled" => true}
      refute Map.has_key?(request[:json], "reasoning_effort")
    end

    test "leaves other providers, effort levels, and provider defaults unchanged", %{config: config} do
      for {provider, body} <- [
            {"openai", %{"reasoning_effort" => "none"}},
            {"together", %{"reasoning_effort" => "high"}},
            {"together", %{}}
          ] do
        binding = %ModelBinding{name: "Alias", upstream_provider: provider, upstream_model: "upstream-model"}

        assert {:ok, request} = Inference.relay_request(binding, body, config: config)
        assert request[:json] == Map.put(body, "model", "upstream-model")
      end
    end
  end

  test "preserves a provider billing rejection from the streaming retry" do
    body =
      JSON.encode!(%{"error" => %{"type" => "credit_limit", "message" => "A positive credit balance is required."}})

    response = %Req.Response{status: 402, headers: %{"content-type" => ["application/json"]}, body: ""}
    {first, last} = String.split_at(body, 30)

    assert {:ok, restored} = Inference.completion_from_stream(response, [last, first])
    assert restored.status == 402
    assert restored.headers == response.headers
    assert restored.body == body
  end

  test "preserves non-success responses even when the provider returns plain text" do
    response = %Req.Response{status: 503, headers: %{"content-type" => ["text/plain"]}, body: ""}

    assert {:ok, restored} = Inference.completion_from_stream(response, ["unavailable", "Service "])
    assert restored.status == 503
    assert restored.body == "Service unavailable"
  end

  test "assembles successful streamed completions" do
    payload = %{
      "id" => "completion-1",
      "created" => 1_759_430_000,
      "model" => "model",
      "choices" => [%{"index" => 0, "delta" => %{"content" => "Hello"}, "finish_reason" => "stop"}]
    }

    stream = "data: #{JSON.encode!(payload)}\n\ndata: [DONE]\n\n"

    assert {:ok, response} = Inference.completion_from_stream(%Req.Response{status: 200}, [stream])

    assert response.body["choices"] == [
             %{"index" => 0, "message" => %{"role" => "assistant", "content" => "Hello"}, "finish_reason" => "stop"}
           ]
  end

  test "assembles fragmented parallel tool calls without losing their names or arguments" do
    deltas = [
      %{"role" => "assistant", "content" => "Checking the sender."},
      %{
        "tool_calls" => [
          %{
            "index" => 0,
            "id" => "call-thread",
            "type" => "function",
            "function" => %{"name" => "find_open_support_thread", "arguments" => "{\"email\":"}
          }
        ]
      },
      %{
        "tool_calls" => [
          %{
            "index" => 1,
            "id" => "call-result",
            "type" => "function",
            "function" => %{"name" => "submit_", "arguments" => "{\"category\":\"pub"}
          },
          %{
            "index" => 0,
            "id" => nil,
            "type" => nil,
            "function" => %{"name" => nil, "arguments" => "\"no-reply@gradle.com\"}"}
          }
        ]
      },
      %{"tool_calls" => [%{"index" => 1, "function" => %{"name" => "result", "arguments" => "lish\"}"}}]},
      %{"tool_calls" => [%{"index" => 1, "function" => %{"name" => nil, "arguments" => nil}}]},
      %{"tool_calls" => [%{"index" => 0, "function" => nil}]},
      %{"tool_calls" => []}
    ]

    stream = completion_stream(deltas, "tool_calls")
    {first, last} = String.split_at(stream, 80)

    assert {:ok, response} = Inference.completion_from_stream(%Req.Response{status: 200}, [last, first])
    [choice] = response.body["choices"]
    assert choice["finish_reason"] == "tool_calls"
    assert choice["message"]["content"] == "Checking the sender."

    assert choice["message"]["tool_calls"] == [
             %{
               "id" => "call-thread",
               "type" => "function",
               "function" => %{
                 "name" => "find_open_support_thread",
                 "arguments" => ~s({"email":"no-reply@gradle.com"})
               }
             },
             %{
               "id" => "call-result",
               "type" => "function",
               "function" => %{"name" => "submit_result", "arguments" => ~s({"category":"publish"})}
             }
           ]
  end

  test "assembles tool-only completions and preserves usage" do
    stream =
      completion_stream(
        [
          %{
            "tool_calls" => [
              %{
                "index" => 0,
                "id" => "call-result",
                "type" => "function",
                "function" => %{"name" => "submit_result", "arguments" => ""}
              }
            ]
          },
          %{"tool_calls" => [%{"index" => 0, "function" => %{"arguments" => ~s({"action_needed":false})}}]}
        ],
        "tool_calls"
      )

    usage = %{"prompt_tokens" => 100, "completion_tokens" => 20, "total_tokens" => 120}
    stream = stream <> "data: #{JSON.encode!(%{"choices" => [], "usage" => usage})}\n\ndata: [DONE]\n\n"

    assert {:ok, response} = Inference.completion_from_stream(%Req.Response{status: 200}, [stream])
    assert response.body["usage"] == usage
    [choice] = response.body["choices"]
    assert choice["message"]["content"] == nil

    assert [
             %{
               "id" => "call-result",
               "type" => "function",
               "function" => %{"name" => "submit_result", "arguments" => arguments}
             }
           ] = choice["message"]["tool_calls"]

    assert JSON.decode!(arguments) == %{"action_needed" => false}
  end

  test "assembles legacy function call argument fragments" do
    stream =
      completion_stream(
        [
          %{"function_call" => %{"name" => "submit_result", "arguments" => "{\"category\":"}},
          %{"function_call" => %{"arguments" => "\"publish\"}"}}
        ],
        "function_call"
      )

    assert {:ok, response} = Inference.completion_from_stream(%Req.Response{status: 200}, [stream])
    [choice] = response.body["choices"]

    assert choice["message"]["function_call"] == %{
             "name" => "submit_result",
             "arguments" => ~s({"category":"publish"})
           }
  end

  test "still rejects malformed successful streams" do
    assert {:error, :invalid_streamed_completion} =
             Inference.completion_from_stream(%Req.Response{status: 200}, ["data: invalid\n\n"])
  end

  defp completion_stream(deltas, finish_reason) do
    events =
      Enum.map(deltas, fn delta ->
        %{
          "id" => "completion-1",
          "created" => 1_759_430_000,
          "model" => "model",
          "choices" => [%{"index" => 0, "delta" => delta}]
        }
      end)

    finish = %{"choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => finish_reason}]}

    Enum.map_join(events ++ [finish], "", &"data: #{JSON.encode!(&1)}\n\n")
  end
end
