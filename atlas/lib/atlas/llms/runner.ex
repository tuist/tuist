defmodule Atlas.LLMs.Runner do
  @moduledoc """
  Shared plumbing for AI feature agents.

  Resolves the global `Atlas.LLMs.config/0` map into the keyword list
  consumed by `Helmsman.start_link/1` / `Condukt.start_link/1`, and
  builds the ReqLLM model spec from a `provider:model_id` string.

  Domain agents live in their own context (`Atlas.Accounts.Agents.*`);
  this module is the only piece of LLM infrastructure they share.
  """

  alias Atlas.LLMs.LocalTransport

  @doc """
  Returns the configured LLM as `{:ok, map}` or `{:error, :llm_not_configured}`.
  """
  def fetch_config do
    case Atlas.LLMs.config() do
      nil -> {:error, :llm_not_configured}
      llm -> {:ok, llm}
    end
  end

  @doc """
  Builds the keyword list passed to a session `start_link/1`:
  `[model: %ReqLLM.Model{}, api_key: ..., base_url: ..., timeout: ...]`.
  Optional keys are omitted when the config doesn't override them.

  In local mode, the plug spec is injected under `llm_request_options`
  so Condukt threads it into every ReqLLM call via `req_http_options`,
  and Req dispatches through `LocalTransport` instead of the network.
  The `api_key`, `base_url`, and `model` are set to sentinel values
  because none of them travel outside the process — `LocalTransport`
  looks up the profile marked as the default for the atlas role
  (`atlas_inference` for chat, `atlas_embedding` for embeddings) and
  rewrites the model identifier to that profile's name before
  delegating to the controller.
  """
  def client_opts(%{mode: :local} = llm) do
    [
      # ReqLLM's OpenAI provider validates that `model.provider == :openai`
      # to select the right request shape (Atlas.Inference speaks the
      # OpenAI-compatible surface). The `id` is a sentinel — LocalTransport
      # replaces it with the current default profile's name.
      model: ReqLLM.model!(%{id: "atlas-default", provider: :openai}),
      api_key: "local",
      base_url: "http://atlas-local",
      # Condukt only forwards `req_http_options` when it lives inside
      # `llm_request_options`; a top-level key is silently dropped, so the
      # plug never reaches ReqLLM and requests escape to the sentinel host.
      llm_request_options: [req_http_options: [plug: {LocalTransport, []}]]
    ]
    |> maybe_put(:timeout, operation_timeout(llm))
    |> Keyword.put(:retry, false)
  end

  def client_opts(%{model: _, api_key: api_key} = llm) do
    [model: build_model(llm), api_key: api_key]
    |> maybe_put(:base_url, Map.get(llm, :base_url))
    |> maybe_put(:timeout, operation_timeout(llm))
    |> Keyword.put(:retry, false)
  end

  defp build_model(%{model: model}) do
    case String.split(model, ":", parts: 2) do
      [provider_name, model_id] ->
        ReqLLM.model!(%{
          id: model_id,
          provider: provider(provider_name)
        })

      _ ->
        model
    end
  end

  defp provider("openai"), do: :openai

  defp provider(provider_name) do
    raise ArgumentError, "unsupported LLM provider: #{provider_name}"
  end

  defp operation_timeout(llm) do
    case Map.get(llm, :receive_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout + :timer.seconds(30)
      _ -> nil
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
