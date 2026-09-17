defmodule Atlas.LLMsTest do
  use ExUnit.Case, async: true

  alias Atlas.LLMs

  describe "config/1" do
    test "returns nil when the API key is missing" do
      assert is_nil(LLMs.config(model: "custom-model"))
    end

    test "returns nil when the API key is blank" do
      assert is_nil(LLMs.config(api_key: "", model: "custom-model"))
    end

    test "returns the configured LLM values" do
      assert %{
               api_key: "api-key",
               model: "custom-model",
               base_url: "https://llm.example",
               receive_timeout: 300_000
             } =
               LLMs.config(
                 api_key: "api-key",
                 model: "custom-model",
                 base_url: "https://llm.example",
                 receive_timeout: 300_000
               )
    end
  end
end
