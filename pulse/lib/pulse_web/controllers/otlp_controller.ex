defmodule PulseWeb.OTLPController do
  use PulseWeb, :controller

  @doc "OTLP/HTTP JSON or protobuf logs, optionally gzip, at POST /v1/logs."
  def logs(conn, _params), do: PulseWeb.OTLPHTTP.export(conn, :logs)
end
