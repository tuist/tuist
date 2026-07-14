defmodule TuistWeb.RateLimit.Grafana do
  @moduledoc """
  Rate limiting for the Grafana internal read-only DB query endpoint.
  """

  alias TuistWeb.RateLimit.InMemory

  def hit(conn) do
    conn
    |> key()
    |> InMemory.hit(to_timeout(minute: 1), Tuist.Environment.grafana_rate_limit_bucket_size())
  end

  defp key(conn), do: "grafana:ip:#{TuistWeb.RemoteIp.get(conn)}"
end
