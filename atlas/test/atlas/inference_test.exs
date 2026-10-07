defmodule Atlas.InferenceTest do
  use ExUnit.Case, async: true

  alias Atlas.Inference

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

  test "still rejects malformed successful streams" do
    assert {:error, :invalid_streamed_completion} =
             Inference.completion_from_stream(%Req.Response{status: 200}, ["data: invalid\n\n"])
  end
end
