defmodule SymptomsWeb.MetricsController do
  @moduledoc """
  `GET /metrics`: Prometheus text for the evaluator's heartbeat and coverage,
  scraped into Grafana Cloud for the watcher alert. The metric names are in
  `symptoms/README.md` "Backstops and watching the watcher".
  """
  use Phoenix.Controller, formats: []

  def show(conn, _params) do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain; version=0.0.4")
    |> Plug.Conn.send_resp(200, Symptoms.Metrics.render(DateTime.utc_now()))
  end
end
