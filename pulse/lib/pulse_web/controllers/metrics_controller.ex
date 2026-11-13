defmodule PulseWeb.MetricsController do
  use PulseWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/plain", "utf-8")
    |> put_resp_header("content-type", "text/plain; version=0.0.4; charset=utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, Pulse.SelfMetrics.render() <> Pulse.Metrics.render())
  end
end
