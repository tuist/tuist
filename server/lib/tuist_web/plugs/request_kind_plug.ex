defmodule TuistWeb.Plugs.RequestKindPlug do
  @moduledoc """
  Tags requests with a coarse `request_kind` (e.g. `"page_load"`, `"api"`,
  `"mcp"`) for observability.

  Installed once at the `Endpoint` level. Pipelines declare their kind by
  assigning `:request_kind` to the conn (see `TuistWeb.Router`'s
  `put_request_kind/2`). When the response is being sent, this plug's
  `before_send` callback copies the kind into `Logger.metadata` and the
  active OpenTelemetry span — at which point it is in scope for the
  `Plug.Telemetry` `:stop` callback that emits the `Sent NNN in NNNms`
  log line, which is what observability dashboards filter on.

  Routes that don't run through a tagged pipeline (webhooks, static
  assets) flow through with no kind set; downstream filters can either
  match the absence (`| request_kind=\"\"`) or just exclude them by
  matching specific kinds.
  """

  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, &put_request_kind_metadata/1)
  end

  defp put_request_kind_metadata(conn) do
    case conn.assigns[:request_kind] do
      kind when is_binary(kind) ->
        Logger.metadata(request_kind: kind)
        OpenTelemetry.Tracer.set_attribute("request_kind", kind)

      _ ->
        :ok
    end

    conn
  end
end
