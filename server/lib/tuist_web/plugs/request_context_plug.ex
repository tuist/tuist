defmodule TuistWeb.Plugs.RequestContextPlug do
  @moduledoc """
  Captures request context (path, method) early in the plug pipeline for debugging.

  This plug runs before Plug.Parsers so that even if body reading fails with a timeout,
  we still have context about which endpoint was being called.
  """

  @behaviour Plug

  def init(opts) do
    error_tracking_enabled_fn =
      Keyword.get(opts, :error_tracking_enabled_fn, &Tuist.Environment.error_tracking_enabled?/0)

    %{error_tracking_enabled_fn: error_tracking_enabled_fn}
  end

  def call(conn, %{error_tracking_enabled_fn: error_tracking_enabled_fn}) do
    if error_tracking_enabled_fn.() do
      span = Appsignal.Tracer.root_span()

      if span do
        Appsignal.Span.set_sample_data(span, "request_context", %{
          path: conn.request_path,
          method: conn.method,
          query_string: conn.query_string
        })
      end
    end

    conn
  end
end
