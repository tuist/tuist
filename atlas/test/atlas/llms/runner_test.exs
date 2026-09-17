defmodule Atlas.LLMs.RunnerTest do
  use ExUnit.Case, async: true

  alias Atlas.LLMs.Runner

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
  end
end
