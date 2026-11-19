defmodule Atlas.LLMs.PersonalTransport do
  @moduledoc """
  Buffered Orbit model transport, inside ModelFence. Tries the acting person's
  ChatGPT account, then Claude, then only the configured Orbit inference role.
  Credentials never enter Condukt options, snapshots, or provider error bodies.
  Each turn (including children and resumed runs) reloads the same user's accounts.
  """

  @behaviour Plug

  import Plug.Conn

  alias Atlas.Inference
  alias Atlas.LLMs.Connections
  alias Atlas.LLMs.LocalTransport
  alias Atlas.LLMs.PersonalProviders
  alias Atlas.Orbit.ModelFence
  alias Atlas.Repo
  alias Atlas.Users.User

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    with %User{} = user <- Repo.get(User, Keyword.fetch!(opts, :user_id)),
         {:ok, body, conn} <- read_body(conn),
         {:ok, params} when is_map(params) <- JSON.decode(body) do
      choice = Keyword.get(opts, :model)

      case completion(conn, user, params, choice) do
        {:ok, completion} -> respond(conn, 200, completion)
        {:stop, status, category} -> unavailable(conn, status, Atom.to_string(category))
        {:fallback, failure} -> fallback(conn, params, failure)
      end
    else
      _ -> unavailable(conn, 503)
    end
  end

  defp completion(conn, user, params, nil), do: personal_completion(conn, user, params, ["chatgpt", "claude"], nil)

  defp completion(_conn, _user, _params, "workspace"), do: {:fallback, nil}

  defp completion(conn, user, params, "chatgpt:" <> model) do
    with {:ok, %{access_token: token}} <- Connections.credentials(user, "chatgpt"),
         {:ok, reply} <- authorized_completion(conn, "chatgpt", token, Map.put(params, "model", model)) do
      {:ok, reply}
    else
      {:error, status, category} -> {:stop, status, category}
      {:error, _reason} -> {:stop, 401, :provider_auth}
    end
  end

  defp personal_completion(_conn, _user, _params, [], last_status), do: {:fallback, last_status}

  defp personal_completion(conn, user, params, [provider | rest], last_status) do
    case Connections.credentials(user, provider) do
      {:ok, %{access_token: token}} ->
        case authorized_completion(
               conn,
               provider,
               token,
               Map.put(params, "model", PersonalProviders.default_model(provider))
             ) do
          {:ok, completion} ->
            {:ok, completion}

          {:error, status, category} when status in [401, 402, 403, 408, 429] or status >= 500 ->
            personal_completion(conn, user, params, rest, {status, Atom.to_string(category)})

          {:error, status, category} ->
            {:stop, status, category}
        end

      {:error, :not_connected} ->
        personal_completion(conn, user, params, rest, last_status)

      {:error, _category} ->
        personal_completion(conn, user, params, rest, last_status || {502, "provider_error"})
    end
  end

  defp authorized_completion(conn, provider, token, params) do
    if ModelFence.authorized?(conn),
      do: PersonalProviders.complete(provider, token, params),
      else: {:error, 409, :cancelled}
  end

  defp fallback(conn, params, last_status) do
    cond do
      not ModelFence.authorized?(conn) ->
        unavailable(conn, 409)

      Inference.atlas_role_configured?(:orbit) ->
        # Personal Codex state belongs only to that account, never the workspace provider.
        params =
          update_in(params, ["messages"], &Enum.map(&1, fn message -> Map.delete(message, "reasoning_details") end))

        conn
        |> Map.put(:body_params, params)
        |> LocalTransport.call(role: :orbit)

      true ->
        {status, code} = last_status || {503, "not_configured"}
        unavailable(conn, status, code)
    end
  end

  defp unavailable(conn, status, code \\ "provider_error") do
    respond(conn, status, %{
      error: %{message: "The assistant's inference provider is unavailable.", type: "provider_error", code: code}
    })
  end

  defp respond(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(body))
  end
end
