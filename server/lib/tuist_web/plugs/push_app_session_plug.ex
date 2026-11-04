defmodule TuistWeb.Plugs.PushAppSessionPlug do
  @moduledoc """
  Admits only requests from a signed-in Tuist app (see `Tuist.Push.oauth_session/2`)
  to the `/api/me` push device and notification preference endpoints. It assigns
  `:push_user` and `:push_session`, and marks responses `no-store`. Other OAuth
  clients, account tokens and agent credentials get a 403, whatever their scopes.
  """
  @behaviour Plug

  import Plug.Conn

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Push
  alias TuistWeb.Authentication

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with %User{} = user <- user(Authentication.authenticated_subject(conn)),
         ["Bearer " <> bearer] <- get_req_header(conn, "authorization"),
         {:ok, session} <- Push.oauth_session(bearer, user) do
      conn |> assign(:push_user, user) |> assign(:push_session, session)
    else
      _ ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(%{message: "This can only be managed from a signed-in Tuist app."})
        |> halt()
    end
  end

  defp user(%User{} = user), do: user
  defp user(%AuthenticatedAccount{issued_by: %User{} = user}), do: user
  defp user(_subject), do: nil
end
