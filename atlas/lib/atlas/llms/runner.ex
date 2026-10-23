defmodule Atlas.LLMs.Runner do
  @moduledoc """
  Shared plumbing for AI feature agents.

  Resolves the global `Atlas.LLMs.config/0` map into the keyword list
  consumed by `Condukt.start_link/1`, and builds the ReqLLM model spec
  from a `provider:model_id` string.

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
  delegating to the controller. The `llm_request_options` key is
  honored by Condukt 1.13+ (earlier versions silently dropped it,
  which escaped every chat completion to the sentinel host and
  returned `:nxdomain`).
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

  @doc """
  Builds client options that always dispatch in-process to the profile bound
  to `role`, independent of the global `LLM_MODE`. The transport rejects the
  request when no enabled profile carries that role; it never substitutes the
  global inference profile.
  """
  def profile_client_opts(role, opts \\ []) when is_atom(role) do
    [
      model: ReqLLM.model!(%{id: "atlas-#{role}", provider: :openai}),
      api_key: "local",
      base_url: "http://atlas-local",
      llm_request_options: [req_http_options: [plug: {LocalTransport, role: role}]]
    ]
    |> maybe_put(:timeout, Keyword.get(opts, :timeout))
    |> Keyword.put(:retry, false)
  end

  @doc """
  Supplies reply events to a consumer while owning the transient agent session.

  ReqLLM's streaming transport uses Finch directly and ignores Req's Plug
  adapter. Local mode must use the buffered model path so the sentinel URL
  never reaches the network. Condukt still executes the full model/tool loop;
  only incremental text and tool-status delivery are unavailable in this mode.
  """
  def with_reply_stream(llm, agent_module, prompt, opts, fun) do
    Condukt.Session.with_transient(agent_module, opts, fn agent ->
      events =
        case llm do
          %{mode: :local} -> buffered_reply_events(agent, prompt, opts)
          _ -> Condukt.stream(agent, prompt)
        end

      fun.(events)
    end)
  end

  defp buffered_reply_events(agent, prompt, opts) do
    Stream.flat_map([prompt], fn prompt ->
      case Condukt.run(agent, prompt, opts) do
        {:ok, text} when is_binary(text) -> [{:text, text}, :done]
        {:ok, _other} -> [{:error, :empty_response}]
        {:error, reason} -> [{:error, reason}]
      end
    end)
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
