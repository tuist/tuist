defmodule TuistWeb.RateLimit.Atlas do
  @moduledoc """
  Rate limiting for Atlas internal API endpoints.
  """

  alias TuistWeb.RateLimit.InMemory

  def hit(conn) do
    conn
    |> key()
    |> InMemory.hit(to_timeout(minute: 1), Tuist.Environment.atlas_rate_limit_bucket_size())
  end

  defp key(conn), do: "atlas:ip:#{TuistWeb.RemoteIp.get(conn)}"
end
