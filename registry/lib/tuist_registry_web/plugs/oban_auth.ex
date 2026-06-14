defmodule TuistRegistryWeb.Plugs.ObanAuth do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if TuistRegistry.Config.oban_dashboard_enabled?() do
      Plug.BasicAuth.basic_auth(conn, TuistRegistry.Config.oban_web_credentials())
    else
      conn
      |> send_resp(404, "Not Found")
      |> halt()
    end
  end
end
