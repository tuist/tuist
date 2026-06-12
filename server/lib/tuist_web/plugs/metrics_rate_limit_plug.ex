defmodule TuistWeb.Plugs.MetricsRateLimitPlug do
  @moduledoc false

  use TuistWeb, :controller

  alias TuistWeb.RateLimit

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    case RateLimit.Metrics.hit(conn) do
      {:allow, _} ->
        conn

      {:deny, retry_after_ms} ->
        retry_after_seconds = max(1, div(retry_after_ms, 1000))

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
        |> put_status(:too_many_requests)
        |> json(%{message: "Rate limit exceeded. Please slow down your requests."})
        |> halt()
    end
  end
end
