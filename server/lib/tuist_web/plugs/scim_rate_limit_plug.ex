defmodule TuistWeb.Plugs.SCIMRateLimitPlug do
  @moduledoc false

  import Plug.Conn

  alias Tuist.SCIM.Resource
  alias TuistWeb.RateLimit

  def init(opts), do: opts

  def call(%Plug.Conn{} = conn, _opts) do
    case RateLimit.SCIM.hit(conn) do
      {:allow, _} ->
        conn

      {:deny, _} ->
        body = Resource.render_error(429, "Rate limit exceeded. Please try again later.", "tooManyRequests")

        conn
        |> put_resp_content_type("application/scim+json")
        |> send_resp(429, JSON.encode!(body))
        |> halt()
    end
  end
end
