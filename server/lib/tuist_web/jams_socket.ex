defmodule TuistWeb.JamsSocket do
  @moduledoc false
  use Phoenix.Socket

  alias Tuist.Accounts.User
  alias Tuist.Authentication
  alias TuistWeb.Authentication, as: WebAuthentication

  channel "jams:*", TuistWeb.JamsChannel
  channel "threads:*", TuistWeb.JamsChannel

  # Phoenix extracts this only from the bearer WebSocket subprotocol. Never
  # accept a credential in URL parameters, which are routinely logged.
  def connect(_params, socket, %{auth_token: token}) when is_binary(token) do
    case authenticate(token) do
      {:ok, user} -> {:ok, socket |> assign(:bearer, token) |> assign(:app_user, user)}
      _ -> :error
    end
  end

  def connect(_params, _socket, _info), do: :error

  def id(socket), do: "jams:user:#{socket.assigns.app_user.id}"

  def authenticate(token) do
    subject = Authentication.authenticated_subject(token)

    conn =
      %Plug.Conn{}
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> token)
      |> Plug.Conn.assign(:current_subject, subject)

    case WebAuthentication.app_user(conn) do
      %User{} = user -> {:ok, user}
      _ -> {:error, :unauthenticated}
    end
  end
end
