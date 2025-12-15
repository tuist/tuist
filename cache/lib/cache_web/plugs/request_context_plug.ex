defmodule CacheWeb.Plugs.RequestContextPlug do
  @moduledoc """
  Captures request context (path, method) early in the plug pipeline for debugging.

  This plug runs before Plug.Parsers so that even if body reading fails with a timeout,
  we still have context about which endpoint was being called.
  """

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    if appsignal_active?() do
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

  defp appsignal_active? do
    case Application.get_env(:appsignal, :config) do
      nil -> false
      config -> Keyword.get(config, :active, false)
    end
  end
end
