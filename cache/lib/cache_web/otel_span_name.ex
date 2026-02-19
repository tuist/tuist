defmodule CacheWeb.OtelSpanName do
  @moduledoc """
  Custom telemetry handler that updates OpenTelemetry span names to include
  the Phoenix route pattern (e.g. "POST /api/projects/:account_handle")
  instead of just the HTTP method (e.g. "POST").

  Uses the explicit `OpenTelemetry.Span` API (passing the span context directly)
  rather than the `Tracer` macro, as the macro-based `update_name` in
  `OpentelemetryPhoenix` does not reliably persist the updated name.
  """

  alias OpenTelemetry.SemConv.Incubating.HTTPAttributes

  def setup do
    :telemetry.attach(
      {__MODULE__, :router_dispatch_start},
      [:phoenix, :router_dispatch, :start],
      &__MODULE__.handle_router_dispatch/4,
      %{}
    )
  end

  def handle_router_dispatch(_event, _measurements, meta, _config) do
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()
    OpenTelemetry.Span.update_name(span_ctx, "#{meta.conn.method} #{meta.route}")

    OpenTelemetry.Span.set_attributes(span_ctx, [
      {HTTPAttributes.http_route(), meta.route},
      {:"phoenix.plug", inspect(meta.plug)},
      {:"phoenix.action", meta.plug_opts}
    ])
  end
end
