defmodule CacheWeb.Plugs.RequestContextPlug do
  @moduledoc """
  Captures request context (path, method) early in the plug pipeline for debugging.

  This plug runs before Plug.Parsers so that even if body reading fails with a timeout,
  we still have context about which endpoint was being called.
  """

  @behaviour Plug

  def init(opts) do
    appsignal_active_fn =
      Keyword.get(opts, :appsignal_active_fn, &__MODULE__.appsignal_active?/0)

    %{appsignal_active_fn: appsignal_active_fn}
  end

  def call(conn, %{appsignal_active_fn: appsignal_active_fn}) do
    if appsignal_active_fn.() do
      span = Appsignal.Tracer.root_span()

      if span do
        Appsignal.Span.set_sample_data(span, "custom_data", %{
          request_path: conn.request_path,
          request_method: conn.method,
          request_query_string: conn.query_string
        })
      end
    end

    conn
  end

  @doc false
  def appsignal_active? do
    case Application.get_env(:appsignal, :config) do
      nil -> false
      config -> config[:active] || false
    end
  end
end
