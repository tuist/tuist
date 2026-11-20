defmodule TuistWeb.API.LuftNotificationsController do
  @moduledoc "User-delegated notification transport for the configured Luft server."
  use TuistWeb, :controller

  alias Tuist.Push
  alias TuistWeb.Authentication

  def create(conn, params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with user when not is_nil(user) <- Authentication.oauth_user(conn),
         ["Bearer " <> bearer] <- get_req_header(conn, "authorization") do
      case Push.dispatch_luft(user, bearer, params) do
        :ok -> send_resp(conn, 204, "")
        {:error, :forbidden} -> failure(conn, 403, "forbidden")
        {:error, :invalid} -> failure(conn, 400, "invalid")
        {:error, :invalid_token} -> failure(conn, 410, "invalid_token")
        {:error, {:rejected, _}} -> failure(conn, 422, "rejected")
        _ -> failure(conn, 503, "unavailable")
      end
    else
      _ -> failure(conn, 403, "forbidden")
    end
  end

  defp failure(conn, status, code), do: conn |> put_status(status) |> json(%{code: code})
end
