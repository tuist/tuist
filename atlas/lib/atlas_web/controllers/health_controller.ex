defmodule AtlasWeb.HealthController do
  use AtlasWeb, :controller

  def ready(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
