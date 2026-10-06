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

  # No field of any request holds an integer wider than 64 bits. One that is
  # makes the validation library raise when it converts the integer to a
  # float, before any schema limit is looked at, so it is refused here.
  @integers -0x8000000000000000..0xFFFFFFFFFFFFFFFF

  @impl true
  def call(conn, opts) do
    if integers_fit?(conn.body_params) do
      OpenTelemetry.Tracer.with_span "openapi_spex.cast_and_validate" do
        CastAndValidate.call(conn, opts)
      end
    else
      conn
      |> Plug.Conn.put_status(:bad_request)
      |> Phoenix.Controller.json(%{message: "A number in the request is out of range."})
      |> Plug.Conn.halt()
    end
  end

  defp integers_fit?(value) when is_integer(value), do: value in @integers
  defp integers_fit?(value) when is_list(value), do: Enum.all?(value, &integers_fit?/1)
  defp integers_fit?(%_struct{}), do: true
  defp integers_fit?(value) when is_map(value), do: Enum.all?(value, fn {_key, value} -> integers_fit?(value) end)
  defp integers_fit?(_value), do: true
end
