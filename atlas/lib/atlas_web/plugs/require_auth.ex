defmodule AtlasWeb.Plugs.RequireAuth do
  import Phoenix.Controller
  import Plug.Conn

  alias Atlas.Users

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_id) do
      nil ->
        conn
        |> store_return_to()
        |> redirect(to: "/login")
        |> halt()

      user_id ->
        case Users.get_user(user_id) do
          nil ->
            conn
            |> configure_session(drop: true)
            |> store_return_to()
            |> redirect(to: "/login")
            |> halt()

          user ->
            assign(conn, :current_user, user)
        end
    end
  end

  # Only stash safe local paths (`/foo/bar[?q]`) so a poisoned
  # `return_to` cannot bounce the browser to another origin after login.
  defp store_return_to(%Plug.Conn{method: "GET"} = conn) do
    case build_return_to(conn.request_path, conn.query_string) do
      nil -> conn
      path -> put_session(conn, :return_to, path)
    end
  end

  defp store_return_to(conn), do: conn

  defp build_return_to(path, query) when is_binary(path) do
    cond do
      path in ["", "/", "/login", "/dev/login"] -> nil
      not local_path?(path) -> nil
      is_binary(query) and query != "" -> path <> "?" <> query
      true -> path
    end
  end

  defp build_return_to(_path, _query), do: nil

  defp local_path?("/" <> rest), do: not String.starts_with?(rest, "/")
  defp local_path?(_path), do: false
end
