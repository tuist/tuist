defmodule Condukt.Providers.OllamaTest do
  use ExUnit.Case, async: true

  test "keeps the legacy direct provider while using ReqLLM's built-in provider by default" do
    assert Condukt.Providers.Ollama.provider_id() == :ollama
    assert {:ok, ReqLLM.Providers.Ollama} = ReqLLM.Providers.get(:ollama)
  end
end
