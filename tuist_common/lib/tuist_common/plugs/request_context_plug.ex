defmodule TuistCommon.Plugs.RequestContextPlug do
  @moduledoc """
  Captures request context (path, method) early in the plug pipeline for debugging.

  This plug runs before Plug.Parsers so that even if body reading fails with a timeout,
  we still have context about which endpoint was being called.

  ## Options

  - `:enabled_fn` - A zero-arity function that returns a boolean. When `true`,
    request context is captured to AppSignal. Defaults to checking AppSignal config.
  """

  @behaviour Plug

  def init(opts) do
    enabled_fn = Keyword.get(opts, :enabled_fn, {__MODULE__, :appsignal_active?, []})
    %{enabled_fn: enabled_fn}
  end

  def call(conn, %{enabled_fn: enabled_fn}) do
    enabled? =
      case enabled_fn do
        {mod, fun, args} -> apply(mod, fun, args)
        fun when is_function(fun, 0) -> fun.()
      end

    if enabled? do
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
