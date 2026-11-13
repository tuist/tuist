defmodule Condukt.Test.LLMProvider do
  @moduledoc false

  use ReqLLM.Provider,
    id: :condukt_test,
    default_base_url: "http://condukt.test"

  alias ReqLLM.Message
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.Response

  @store __MODULE__.Store

  @impl true
  def prepare_request(:chat, model, context, opts) do
    case take_response(model.id) do
      {:ok, owner, {:error, reason}} ->
        send(owner, {__MODULE__, :request, model.id, context, opts})
        {:error, reason}

      {:ok, owner, response} ->
        send(owner, {__MODULE__, :request, model.id, context, opts})
        response = if is_function(response, 0), do: response.(), else: response

        {:ok,
         Req.new(
           method: :post,
           url: default_base_url() <> "/chat",
           adapter: fn request ->
             {request, Req.Response.new(status: 200, body: response)}
           end
         )}

      {:error, message} ->
        {:error, RuntimeError.exception(message)}
    end
  end

  def prepare_request(operation, _model, _context, _opts) do
    {:error, RuntimeError.exception("unexpected test provider operation: #{inspect(operation)}")}
  end

  @impl true
  def attach_stream(model, context, opts, _finch_name) do
    send(owner(model.id), {__MODULE__, :stream_request, model.id, context, opts})
    {:error, RuntimeError.exception("test provider does not stream")}
  end

  def model(responses, opts \\ []) do
    start()

    owner = Keyword.get(opts, :owner, self())
    model_id = Keyword.get(opts, :id, "condukt-test-#{System.unique_integer([:positive])}")

    Agent.update(@store, &Map.put(&1, model_id, {owner, List.wrap(responses)}))

    {%{provider: provider_id(), id: model_id}, model_id}
  end

  def response(%Message{} = message, finish_reason) do
    %Response{
      id: "resp_#{System.unique_integer([:positive])}",
      model: "test:model",
      context: nil,
      message: message,
      object: nil,
      stream?: false,
      stream: nil,
      usage: nil,
      finish_reason: finish_reason,
      provider_meta: %{},
      error: nil
    }
  end

  def text_response(text, finish_reason \\ :stop) when is_binary(text) do
    message = %Message{
      role: :assistant,
      content: [ContentPart.text(text)],
      tool_calls: nil
    }

    response(message, finish_reason)
  end

  defp start do
    ensure_store()
    ReqLLM.Providers.register(__MODULE__)
    :ok
  end

  defp ensure_store do
    case Process.whereis(@store) do
      nil ->
        case Agent.start(fn -> %{} end, name: @store) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _ ->
        :ok
    end
  end

  defp take_response(model_id) do
    start()

    Agent.get_and_update(@store, fn scripts ->
      case Map.fetch(scripts, model_id) do
        {:ok, {owner, [response | rest]}} ->
          {{:ok, owner, response}, Map.put(scripts, model_id, {owner, rest})}

        {:ok, {_owner, []}} ->
          {{:error, "no scripted ReqLLM response left for #{inspect(model_id)}"}, scripts}

        :error ->
          {{:error, "no scripted ReqLLM responses for #{inspect(model_id)}"}, scripts}
      end
    end)
  end

  defp owner(model_id) do
    caller = self()

    Agent.get(@store, fn scripts ->
      case Map.fetch(scripts, model_id) do
        {:ok, {owner, _responses}} -> owner
        :error -> caller
      end
    end)
  end
end
