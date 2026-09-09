defmodule TuistCommon.RequestLoggerPlug do
  @moduledoc false

  @behaviour Plug

  require Logger

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    started_at = System.monotonic_time()

    Plug.Conn.register_before_send(conn, fn conn ->
      duration_ms =
        started_at
        |> then(&(System.monotonic_time() - &1))
        |> System.convert_time_unit(:native, :microsecond)
        |> Kernel./(1_000)

      Logger.info("Request completed",
        method: conn.method,
        route: conn.private[:phoenix_route],
        request_path: conn.request_path,
        status: conn.status,
        duration_ms: duration_ms
      )

      conn
    end)
  end
end
