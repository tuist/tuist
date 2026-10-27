defmodule TuistWeb.RateLimit.Atlas do
  @moduledoc """
  Rate limiting for Atlas internal API endpoints.
  """

  alias TuistWeb.RateLimit

  def hit(conn) do
    RateLimit.hit(
      key(conn),
      limit: Tuist.Environment.atlas_rate_limit_bucket_size(),
      window: to_timeout(minute: 1)
    )
  end

  defp key(conn), do: "atlas:ip:#{TuistWeb.RemoteIp.get(conn)}"
end
