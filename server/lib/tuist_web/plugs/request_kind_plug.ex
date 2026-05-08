defmodule TuistWeb.Plugs.RequestKindPlug do
  @moduledoc """
  Tags the request with a coarse `request_kind` (e.g. `"page_load"`, `"api"`,
  `"mcp"`) in `Logger.metadata` and the active OpenTelemetry span.

  The metadata key is propagated as a Loki structured-metadata field by the
  handler configured in `Tuist.Application`, which lets observability
  dashboards filter request types explicitly instead of inferring them from
  URL shape or the presence of unrelated metadata.
  """

  require Logger

  def init(kind) when is_binary(kind), do: kind

  def call(conn, kind) do
    Logger.metadata(request_kind: kind)
    OpenTelemetry.Tracer.set_attribute("request_kind", kind)
    conn
  end
end
