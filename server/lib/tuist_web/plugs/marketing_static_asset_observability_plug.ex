defmodule TuistWeb.Plugs.MarketingStaticAssetObservabilityPlug do
  @moduledoc """
  Emits timing logs for marketing static assets served before endpoint telemetry runs.
  """

  import Plug.Conn

  require Logger

  @request_kind "marketing_static_asset"

  def init(opts), do: opts

  def call(%{method: method} = conn, _opts) when method in ["GET", "HEAD"] do
    if marketing_static_asset?(conn.path_info) do
      started_at = System.monotonic_time()

      register_before_send(conn, fn conn ->
        maybe_log_static_response(conn, started_at)
        conn
      end)
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp maybe_log_static_response(%{halted: true, status: status}, started_at) when is_integer(status) do
    duration_ms =
      System.monotonic_time()
      |> Kernel.-(started_at)
      |> System.convert_time_unit(:native, :millisecond)

    Logger.metadata(request_kind: @request_kind)
    Logger.info("Sent #{status} in #{duration_ms}ms")
  end

  defp maybe_log_static_response(_conn, _started_at), do: :ok

  defp marketing_static_asset?(["marketing", "assets" | _]), do: true
  defp marketing_static_asset?(["marketing", "images" | _]), do: true
  defp marketing_static_asset?(_path_info), do: false
end
