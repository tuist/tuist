defmodule Condukt.Session.TranslateTest do
  use ExUnit.Case, async: true

  alias Condukt.Session.Translate
  alias Condukt.SessionStore.Snapshot
  alias ReqLLM.Message.ReasoningDetails

  test "opaque reasoning survives tool translation and snapshot restoration without becoming display text" do
    details = [
      %ReasoningDetails{
        signature: "opaque-state",
        encrypted?: true,
        provider: :openai,
        provider_data: %{"id" => "rs_1", "summary" => []}
      }
    ]

    for calls <- [[], [%{id: "call_1", name: "lookup", arguments: %{"query" => "status"}}]] do
      message = %{ReqLLM.Context.assistant("Looking it up", tool_calls: calls) | reasoning_details: details}

      response = %ReqLLM.Response{
        message: message,
        model: "test-model",
        context: ReqLLM.Context.new(),
        id: "response_1"
      }

      translated = Translate.response_to_message(response)
      snapshot = Snapshot.new(%{messages: [translated]})
      assert {:ok, restored} = snapshot |> :erlang.term_to_binary() |> :erlang.binary_to_term() |> Snapshot.migrate()
      [replayed] = Translate.context(restored.messages, nil, nil).messages
      assert replayed.reasoning_details == details
      assert replayed.tool_calls == message.tool_calls
      assert Condukt.Message.text(translated) == "Looking it up"
      assert Condukt.Message.thinking(translated) == nil
    end
  end

  describe "llm_opts/2" do
    test "omits every unset option so the provider's own defaults apply" do
      assert Translate.llm_opts([], []) == []
    end

    test "carries the api key, base url, and tools" do
      opts = Translate.llm_opts([api_key: "sk-test", base_url: "https://proxy.test/v1"], [:tool])

      assert opts[:api_key] == "sk-test"
      assert opts[:base_url] == "https://proxy.test/v1"
      assert opts[:tools] == [:tool]
    end

    # A reasoning model spends the output budget thinking before it writes any
    # answer, so a ceiling sized for the answer alone truncates the response
    # mid-thought and returns empty content.
    test "carries an output-token ceiling when one is configured" do
      assert Translate.llm_opts([max_tokens: 16_384], [])[:max_tokens] == 16_384
    end

    test "omits the ceiling when it is unset" do
      refute Keyword.has_key?(Translate.llm_opts([max_tokens: nil], []), :max_tokens)
    end

    test "translates the thinking level into a reasoning effort" do
      assert Translate.llm_opts([thinking_level: :off], [])[:reasoning_effort] == :none
      assert Translate.llm_opts([thinking_level: :high], [])[:reasoning_effort] == :high
      refute Keyword.has_key?(Translate.llm_opts([thinking_level: nil], []), :reasoning_effort)
    end
  end
end
