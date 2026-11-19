defmodule Condukt.Test.LLMProvider do
  @moduledoc false
  # Scripted ReqLLM provider. `model/2` registers the responses a model id
  # gives, in order. A plain response answers `ReqLLM.generate_text/3`; a
  # `stream_response/2` entry answers `ReqLLM.stream_text/3` through ReqLLM's
  # real streaming path: Finch reads server-sent events from a local HTTP
  # server (`start_event_server/0`), and the provider's default decoder turns
  # them into chunks.

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

  # Streams only when the next scripted response is a stream, so a test that
  # scripts plain responses still sees streaming fail as it always has.
  @impl true
  def attach_stream(model, context, opts, _finch_name) do
    send(owner(model.id), {__MODULE__, :stream_request, model.id, context, opts})

    case take_stream(model.id) do
      {:ok, events} ->
        token = Integer.to_string(System.unique_integer([:positive]))
        Agent.update(@store, &Map.put(&1, {:events, token}, events))
        url = "http://127.0.0.1:#{:persistent_term.get(__MODULE__.EventServer)}/#{token}"
        {:ok, Finch.build(:post, url, [{"content-type", "application/json"}], "{}")}

      :error ->
        {:error, RuntimeError.exception("test provider has no scripted stream")}
    end
  end

  @doc """
  A scripted streamed response, sent as OpenAI chat-completion events.

  Parts are `{:text, chunk}`, `{:tool_call, id, name, args}`, and `:hold`,
  which stops sending without ending the response, as a provider would while
  the process consuming it dies. A response without `:hold` ends with
  `finish_reason`, which defaults to `:tool_calls` when it has tool calls.
  """
  def stream_response(parts, finish_reason \\ nil) do
    tool_calls? = Enum.any?(parts, &match?({:tool_call, _, _, _}, &1))
    finish_reason = finish_reason || if(tool_calls?, do: :tool_calls, else: :stop)

    events =
      parts
      |> Enum.with_index()
      |> Enum.map(fn
        {:hold, _index} -> :hold
        {{:text, chunk}, _index} -> delta(%{"content" => chunk})
        {{:tool_call, id, name, args}, index} -> delta(%{"tool_calls" => [tool_call_delta(index, id, name, args)]})
      end)

    finish = %{"choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => to_string(finish_reason)}]}
    {:stream, events ++ [finish, "[DONE]"]}
  end

  defp delta(delta), do: %{"choices" => [%{"index" => 0, "delta" => delta}]}

  defp tool_call_delta(index, id, name, args) do
    %{
      "index" => index,
      "id" => id,
      "type" => "function",
      "function" => %{"name" => name, "arguments" => JSON.encode!(args)}
    }
  end

  @doc "Starts the local server streamed responses are read from. Called once, from the test helper."
  def start_event_server do
    start()
    {:ok, server} = Bandit.start_link(plug: __MODULE__.EventServer, ip: :loopback, port: 0, startup_log: false)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    :persistent_term.put(__MODULE__.EventServer, port)
  end

  @doc false
  def take_events(token), do: Agent.get_and_update(@store, &Map.pop(&1, {:events, token}, []))

  defp take_stream(model_id) do
    Agent.get_and_update(@store, fn scripts ->
      case Map.fetch(scripts, model_id) do
        {:ok, {owner, [{:stream, events} | rest]}} -> {{:ok, events}, Map.put(scripts, model_id, {owner, rest})}
        _ -> {:error, scripts}
      end
    end)
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

defmodule Condukt.Test.LLMProvider.EventServer do
  @moduledoc false
  # Serves the events `Condukt.Test.LLMProvider.attach_stream/4` stored under
  # the request path, as server-sent events.

  @behaviour Plug

  import Plug.Conn

  alias Condukt.Test.LLMProvider

  @hold_timeout 10_000

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: [token]} = conn, _opts) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> send_chunked(200)

    Enum.reduce_while(LLMProvider.take_events(token), conn, fn
      # Leaves the response open, then gives up on a reader that never comes back.
      :hold, conn ->
        receive do
        after
          @hold_timeout -> {:halt, conn}
        end

      event, conn ->
        data = if is_binary(event), do: event, else: JSON.encode!(event)

        case chunk(conn, "data: " <> data <> "\n\n") do
          {:ok, conn} -> {:cont, conn}
          {:error, _reason} -> {:halt, conn}
        end
    end)
  end
end
