defmodule PulseWeb.OTLPMetricsController do
  use PulseWeb, :controller

  @doc "OTLP/HTTP JSON or protobuf metrics, optionally gzip, at POST /v1/metrics."
  def create(conn, _params), do: PulseWeb.OTLPHTTP.export(conn, :metrics)
end
