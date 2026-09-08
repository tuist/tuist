defmodule TuistCommon.RequestLoggerPlug do
  @moduledoc false

  @behaviour Plug

  require Logger

  @slow_request_ms 500

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

      if noteworthy?(conn.status, duration_ms) do
        Logger.info("Request completed",
          method: conn.method,
          route: conn.private[:phoenix_route],
          request_path: conn.request_path,
          status: conn.status,
          duration_ms: duration_ms
        )
      end

      conn
    end)
  end

  # Fast successful requests are not logged. One entry per request made this
  # the single largest line in the observability bill: 14.2 GB/day across the
  # cache service and the server, 97% of the cache service's log volume, with
  # no alert or dashboard reading it.
  defp noteworthy?(status, duration_ms) do
    is_nil(status) or status >= 400 or duration_ms >= @slow_request_ms
  end
end
