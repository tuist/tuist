defmodule Atlas.LLMs do
  @moduledoc """
  Reads the global language model configuration from app config.

  A single provider/model is shared by every AI-backed feature. Two modes
  are supported:

    * **Remote** (default): set `LLM_API_KEY` + `LLM_MODEL`, optionally
      `LLM_BASE_URL`. Requests go over HTTP to whatever endpoint the API
      key targets.
    * **Local** (`LLM_MODE=local`): atlas hosts the inference relay
      itself. Requests are routed in-process through
      `Atlas.LLMs.LocalTransport`, which dispatches straight to
      `Atlas.Inference.relay_request/3`. Which profile is used isn't
      configured here — it's the profile marked with the appropriate
      role bit (`atlas_inference: true` for chat, `atlas_embedding: true`
      for embeddings) in the `inference_model_bindings` table. No
      `LLM_API_KEY` and no `LLM_MODEL` needed.

  When neither mode is configured, callers receive
  `{:error, :llm_not_configured}` and features stay disabled.
  """

  @doc """
  Returns the configured language model as a map, or `nil` when unavailable.

  Shape:

    * remote:
      `%{mode: :remote, api_key: String.t(), model: String.t(), base_url: String.t() | nil, receive_timeout: pos_integer() | nil}`
    * local:
      `%{mode: :local, receive_timeout: pos_integer() | nil}`
  """
  def config(conf \\ Application.get_env(:atlas, :llm, [])) do
    cond do
      Keyword.get(conf, :mode) == :local ->
        %{
          mode: :local,
          receive_timeout: Keyword.get(conf, :receive_timeout)
        }

      api_key = Keyword.get(conf, :api_key) ->
        case api_key do
          "" ->
            nil

          _ ->
            %{
              mode: :remote,
              api_key: api_key,
              model: Keyword.fetch!(conf, :model),
              base_url: Keyword.get(conf, :base_url),
              receive_timeout: Keyword.get(conf, :receive_timeout)
            }
        end

      true ->
        nil
    end
  end
end
