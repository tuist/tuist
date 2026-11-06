defmodule TuistWeb.Plugs.AppSessionPlug do
  @moduledoc """
  Admits only requests from a signed-in Tuist app (see `Tuist.Push.oauth_session/2`)
  to the `/api/me` push device and notification rule endpoints. It runs after
  `TuistWeb.AuthenticationPlug`, assigns `:app_user` and `:app_session`, and marks
  responses `no-store`. Other OAuth clients, account tokens and agent credentials
  get a 403, whatever their scopes.

  Writes are limited per user, because unregistering unknown IDs and removing
  devices leave tombstones that outlive the user's devices.
  """
  @behaviour Plug

  import Plug.Conn

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Push
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit

  @writes_per_minute 60

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with %AuthenticatedAccount{issued_by: %User{} = user} <- Authentication.authenticated_subject(conn),
         ["Bearer " <> bearer] <- get_req_header(conn, "authorization"),
         {:ok, session} <- Push.oauth_session(bearer, user) do
      conn |> assign(:app_user, user) |> assign(:app_session, session) |> limit_writes(user)
    else
      _ -> halt_with(conn, :forbidden, "This can only be managed from a signed-in Tuist app.")
    end
  end

  defp limit_writes(%Plug.Conn{method: "GET"} = conn, _user), do: conn

  defp limit_writes(conn, user) do
    case RateLimit.hit("app_session:writes:user:#{user.id}",
           limit: @writes_per_minute,
           window: to_timeout(minute: 1),
           failure_policy: :local
         ) do
      {:allow, _count} ->
        conn

      # The header lets clients wait instead of replaying the write straight into the limit.
      {:deny, retry_after_ms} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(max(1, div(retry_after_ms + 999, 1000))))
        |> halt_with(:too_many_requests, "Too many changes. Try again in a minute.")
    end
  end

  defp halt_with(conn, status, message) do
    conn |> put_status(status) |> Phoenix.Controller.json(%{message: message}) |> halt()
  end
end
