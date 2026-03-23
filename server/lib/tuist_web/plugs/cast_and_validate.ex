defmodule TuistWeb.Plugs.CastAndValidate do
  @moduledoc """
  Wrapper around `OpenApiSpex.Plug.CastAndValidate` that adds an OpenTelemetry
  span so we can measure how long request validation takes for large payloads.
  """
  @behaviour Plug

  alias OpenApiSpex.Plug.CastAndValidate

  require OpenTelemetry.Tracer

  @impl true
  def init(opts), do: CastAndValidate.init(opts)

  @impl true
  def call(conn, opts) do
    OpenTelemetry.Tracer.with_span "openapi_spex.cast_and_validate" do
      CastAndValidate.call(conn, opts)
    end
  end
end
