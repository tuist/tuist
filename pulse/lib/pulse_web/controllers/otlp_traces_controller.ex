defmodule PulseWeb.OTLPTracesController do
  use PulseWeb, :controller

  @doc "OTLP/HTTP traces: JSON or protobuf, optionally gzip-compressed."
  def create(conn, _params), do: PulseWeb.OTLPHTTP.export(conn, :traces)
end
