defmodule LuftServer.Notifications.Transport do
  @moduledoc "Fixed, user-authenticated Tuist notification capability; no provider credentials in Luft."
  alias LuftServer.Config
  alias LuftServer.Sessions

  def deliver(session_id, token, environment, payload, opts) do
    session_id
    |> request(:post, "/api/me/luft-notifications", %{
      "kind" => "liveactivity",
      "token" => token,
      "environment" => environment,
      "payload" => payload,
      "options" => Map.new(opts)
    })
    |> case do
      {:ok, _} -> :ok
      {:error, :unauthorized} -> {:error, :invalid_token}
      {:error, :invalid_token} -> {:error, :invalid_token}
      {:error, reason} when reason in [:invalid, :conflict] -> {:error, {:rejected, reason}}
      {:error, :rejected} -> {:error, {:rejected, :upstream_rejected}}
      {:error, reason} -> {:error, {:retry, reason}}
    end
  end

  def request(session_id, method, path, body \\ nil) do
    with session when not is_nil(session) <- Sessions.get_by_id(session_id),
         {:ok, token} <- Sessions.access_token(session),
         {:ok, response} <-
           Req.request(
             Keyword.merge(
               [
                 method: method,
                 url: Config.tuist_issuer() <> path,
                 auth: {:bearer, token},
                 json: body,
                 redirect: false,
                 retry: false,
                 receive_timeout: 10_000
               ],
               Config.req_options()
             )
           ) do
      case response do
        %{status: status, body: body} when status in 200..299 -> {:ok, body}
        %{status: status} when status in [401, 403] -> {:error, :unauthorized}
        %{status: 410} -> {:error, :invalid_token}
        %{status: 409} -> {:error, :conflict}
        %{status: 400} -> {:error, :invalid}
        %{status: 422} -> {:error, :rejected}
        _ -> {:error, :tuist_unavailable}
      end
    else
      nil -> {:error, :unauthorized}
      {:error, :reauthenticate} -> {:error, :unauthorized}
      _ -> {:error, :tuist_unavailable}
    end
  end
end
