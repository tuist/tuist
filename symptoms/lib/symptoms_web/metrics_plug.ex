defmodule SymptomsWeb.MetricsPlug do
  @moduledoc """
  `GET /metrics`: Prometheus text for the evaluator's heartbeat and coverage,
  scraped into Grafana Cloud for the watcher alert. The metric names are in
  `symptoms/README.md` "Backstops and watching the watcher".

  It is served on its own listener (`config :symptoms, :metrics_port`,
  `SYMPTOMS_METRICS_PORT`), not the API endpoint: the Service and its tailnet
  device expose only the API port, and the NetworkPolicy admits only the
  observability namespace to this one. Every other path answers 404.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "GET", path_info: ["metrics"]} = conn, _opts) do
    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, Symptoms.Metrics.render(DateTime.utc_now()))
  end

  def call(conn, _opts), do: send_resp(conn, 404, "")
end
