defmodule LuftServer.Threads.Provider do
  @moduledoc """
  Buffered Chat Completions transport to the thread owner's own AI
  subscription (`LuftServer.AISubscriptions.Inference`). Options contain only
  explicit delegation IDs and sentinel credentials. Every dispatch reloads that
  exact session and its authoritative Tuist account scope, before and after
  credentials load. No session, provider or credential fallback is permitted.
  """
  @behaviour Plug

  import Plug.Conn

  alias LuftServer.AISubscriptions.Inference
  alias LuftServer.Sessions
  alias LuftServer.Threads.ModelFence
  alias LuftServer.Tuist.Scope

  # Keep in sync with LuftServer.AISubscriptions.Inference. Includes base64
  # expansion of four maximal attachments plus bounded prompt/tool overhead.
  @max_request_bytes 8_388_608

  def default_model(:chatgpt), do: "gpt-6-sol"

  @doc """
  Whether threads can run on a subscription to `provider`. Claude refuses
  its subscriptions for inference outside Claude Code, so only ChatGPT runs.
  """
  def runs_threads?(provider), do: provider == "chatgpt"

  def client_opts(thread) do
    with true <- thread.provider == "chatgpt" and valid_model?(thread.model),
         {:ok, _session, _scope} <- owner(thread) do
      {:ok,
       [
         model:
           ReqLLM.model!(%{
             id: thread.model,
             provider: :openai,
             extra: %{wire: %{protocol: "openai_chat"}}
           }),
         api_key: "luft-delegated-inference",
         base_url: "http://luft-inference.invalid",
         retry: false,
         llm_request_options: [req_http_options: [plug: {__MODULE__, thread: thread}]]
       ]}
    else
      false -> {:error, :model_unavailable}
      error -> error
    end
  end

  def client_opts(_owner, thread), do: client_opts(thread)

  @doc "Loads the owner's exact delegation; never searches sessions by subject."
  def owner(thread) do
    case delegation(thread, thread.owner_session_id, thread.owner_id) do
      {:ok, session, %{can_create_threads: true} = scope} -> {:ok, session, scope}
      _ -> {:error, :delegation_unavailable}
    end
  end

  @doc "Loads the original message author's exact delegation for personal tools."
  def author(thread, message),
    do: delegation(thread, message.author_session_id, message.author_id)

  def delegation(thread, session_id, subject)
      when is_binary(session_id) and is_integer(subject) and is_binary(thread.account_handle) do
    with session when not is_nil(session) <- Sessions.get_by_id(session_id),
         true <- session.user_sub == to_string(subject),
         {:ok, scope} <- Scope.load(session, thread.account_handle),
         true <- scope.user_id == subject and scope.account_id == thread.account_id do
      {:ok, session, scope}
    else
      _ -> {:error, :delegation_unavailable}
    end
  end

  def delegation(_thread, _session_id, _subject), do: {:error, :delegation_unavailable}

  @doc "Fresh catalog using the supplied explicit Luft session."
  def models(session) do
    with live when not is_nil(live) <- Sessions.get_by_id(session.id),
         true <- live.user_sub == session.user_sub do
      {:ok, Inference.models(live.user_sub)}
    else
      _ -> {:error, :models_unavailable}
    end
  end

  def validate_model(session, provider, model) do
    with {:ok, catalog} <- models(session),
         true <- Enum.any?(catalog.models, &(&1["provider"] == provider and &1["id"] == model)) do
      :ok
    else
      _ -> {:error, :model_unavailable}
    end
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    thread = Keyword.fetch!(opts, :thread)

    with true <- ModelFence.authorized?(conn),
         {:ok, session, _scope} <- owner(thread),
         {:ok, body, conn} <- read_request(conn),
         {:ok, params} when is_map(params) <- Jason.decode(body),
         true <- ModelFence.authorized?(conn) do
      params =
        params
        |> Map.take(["messages", "tools"])
        |> Map.merge(%{"model" => thread.model, "provider" => thread.provider, "stream" => false})

      # Authority is rechecked after credentials refresh and before dispatch.
      authorized? = fn ->
        ModelFence.authorized?(conn) and match?({:ok, _, _}, owner(thread))
      end

      case Inference.personal_completion(session.user_sub, params, authorized?) do
        {:ok, completion} ->
          respond(conn, 200, completion)

        {:error, status, _category} when status in [400, 401, 402, 403, 409, 429] ->
          unavailable(conn, status)

        _ ->
          unavailable(conn, 503)
      end
    else
      false -> unavailable(conn, 409)
      {:error, :request_too_large} -> unavailable(conn, 413)
      _ -> unavailable(conn, 403)
    end
  end

  defp read_request(conn) do
    case read_body(conn, length: @max_request_bytes + 1) do
      {:ok, body, conn} when byte_size(body) <= @max_request_bytes -> {:ok, body, conn}
      {:ok, _, _} -> {:error, :request_too_large}
      {:more, _, _} -> {:error, :request_too_large}
      error -> error
    end
  end

  defp valid_model?(model),
    do: is_binary(model) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}\z/, model)

  defp unavailable(conn, status),
    do:
      respond(conn, status, %{
        error: %{
          message: "The delegated inference capability is unavailable.",
          type: "provider_error"
        }
      })

  defp respond(conn, status, body),
    do:
      conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
end
