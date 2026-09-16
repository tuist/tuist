defmodule Atlas.LLMs do
  @moduledoc """
  Reads the global language model configuration from app config.

  A single provider/model is shared by every AI-backed feature. Set
  `LLM_API_KEY` and `LLM_MODEL` in the environment to enable them.
  `LLM_BASE_URL` can override the provider endpoint. When unset, callers receive
  `{:error, :llm_not_configured}` and features stay disabled.
  """

  @doc """
  Returns the configured language model as a map, or `nil` when no key is set.

  Shape:
  `%{api_key: String.t(), model: String.t(), base_url: String.t() | nil, receive_timeout: pos_integer() | nil}`.
  """
  def config(conf \\ Application.get_env(:atlas, :llm, [])) do
    case Keyword.get(conf, :api_key) do
      nil ->
        nil

      "" ->
        nil

      api_key ->
        %{
          api_key: api_key,
          model: Keyword.fetch!(conf, :model),
          base_url: Keyword.get(conf, :base_url),
          receive_timeout: Keyword.get(conf, :receive_timeout)
        }
    end
  end
end
