defmodule AtlasWeb.Plugs.RequireAuth do
  import Phoenix.Controller
  import Plug.Conn

  alias Atlas.Users

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> redirect(to: unauthenticated_redirect_path(conn))
        |> halt()

      user_id ->
        case Users.get_user(user_id) do
          nil ->
            conn
            |> configure_session(drop: true)
            |> redirect(to: unauthenticated_redirect_path(conn))
            |> halt()

          user ->
            assign(conn, :current_user, user)
        end
    end
  end

  defp unauthenticated_redirect_path(%Plug.Conn{path_info: ["engineering", "postmortems", number]}) do
    case Integer.parse(number) do
      {_number, ""} -> "/p/postmortems/#{number}"
      _ -> "/login"
    end
  end

  defp unauthenticated_redirect_path(_conn), do: "/login"
end
