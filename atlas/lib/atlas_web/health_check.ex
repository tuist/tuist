defmodule AtlasWeb.HealthCheck do
  import Plug.Conn

  def init(opts), do: opts

  def call(%{request_path: "/up"} = conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
