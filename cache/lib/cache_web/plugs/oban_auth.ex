defmodule CacheWeb.Plugs.ObanAuth do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Cache.Config.oban_dashboard_enabled?() do
      Plug.BasicAuth.basic_auth(conn, Cache.Config.oban_web_credentials())
    else
      conn
      |> send_resp(404, "Not Found")
      |> halt()
    end
  end
end
