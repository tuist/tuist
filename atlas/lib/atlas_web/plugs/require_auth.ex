defmodule AtlasWeb.Plugs.RequireAuth do
  import Phoenix.Controller
  import Plug.Conn

  alias Atlas.Users

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> redirect(to: "/login")
        |> halt()

      user_id ->
        case Users.get_user(user_id) do
          nil ->
            conn
            |> configure_session(drop: true)
            |> redirect(to: "/login")
            |> halt()

          user ->
            assign(conn, :current_user, user)
        end
    end
  end
end
