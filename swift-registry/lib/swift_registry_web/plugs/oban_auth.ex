defmodule SwiftRegistryWeb.Plugs.ObanAuth do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if SwiftRegistry.Config.oban_dashboard_enabled?() do
      Plug.BasicAuth.basic_auth(conn, SwiftRegistry.Config.oban_web_credentials())
    else
      conn
      |> send_resp(404, "Not Found")
      |> halt()
    end
  end
end
