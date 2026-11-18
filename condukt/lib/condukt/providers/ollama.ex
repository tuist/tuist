defmodule Condukt.Providers.Ollama do
  @moduledoc """
  Legacy Ollama provider retained for applications that register it directly.

  Condukt leaves `ollama:` model identifiers to [ReqLLM](https://hexdocs.pm/req_llm)'s built-in provider,
  which supports Ollama's current option set. This module is not registered by
  Condukt and remains only to preserve the direct provider API.
  """

  use ReqLLM.Provider,
    id: :ollama,
    default_base_url: "http://localhost:11434/v1",
    default_env_key: "OLLAMA_API_KEY"

  use ReqLLM.Provider.Defaults

  @provider_schema []
end
