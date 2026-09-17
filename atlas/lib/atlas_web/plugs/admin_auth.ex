defmodule AtlasWeb.Plugs.AdminAuth do
  @moduledoc """
  Basic authentication for admin dashboards (Oban, LiveDashboard).
  Credentials are configured via ADMIN_PASSWORD environment variable.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:atlas, :admin_password) do
      nil ->
        conn
        |> send_resp(
          403,
          "Admin dashboard is not configured. Set SUPER_ADMIN_PASSWORD env variable."
        )
        |> halt()

      password ->
        Plug.BasicAuth.basic_auth(conn, username: "admin", password: password)
    end
  end
end
