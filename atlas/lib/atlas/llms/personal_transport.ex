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
      case personal_completion(conn, user, params, ["chatgpt", "claude"], nil) do
        {:ok, completion} -> respond(conn, 200, completion)
        {:stop, status} -> unavailable(conn, status)
        {:fallback, status} -> fallback(conn, params, status)
      end
    else
      _ -> unavailable(conn, 503)
    end
  end

  defp personal_completion(_conn, _user, _params, [], last_status), do: {:fallback, last_status}

  defp personal_completion(conn, user, params, [provider | rest], last_status) do
    case Connections.credentials(user, provider) do
      {:ok, %{access_token: token}} ->
        result =
          if ModelFence.authorized?(conn),
            do: PersonalProviders.complete(provider, token, params),
            else: {:error, 409}

        case result do
          {:ok, completion} ->
            {:ok, completion}

          {:error, status} when status in [401, 402, 403, 408, 429] or status >= 500 ->
            personal_completion(conn, user, params, rest, status)

          {:error, status} ->
            {:stop, status}
        end

      {:error, :not_connected} ->
        personal_completion(conn, user, params, rest, last_status)

      {:error, _category} ->
        personal_completion(conn, user, params, rest, last_status || 502)
    end
  end

  defp fallback(conn, params, last_status) do
    cond do
      not ModelFence.authorized?(conn) ->
        unavailable(conn, 409)

      Inference.atlas_role_configured?(:orbit) ->
        conn
        |> Map.put(:body_params, params)
        |> LocalTransport.call(role: :orbit)

      true ->
        unavailable(conn, last_status || 503, if(last_status, do: "provider_error", else: "not_configured"))
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
