defmodule TuistCommon.OtelRequestIdPlug do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Plug.Conn.get_resp_header(conn, "x-request-id") do
      [request_id | _] ->
        OpenTelemetry.Tracer.set_attribute("http.request_id", request_id)

      _ ->
        :ok
    end

    conn
  end
end
