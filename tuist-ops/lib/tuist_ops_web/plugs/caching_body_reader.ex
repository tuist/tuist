defmodule TuistOpsWeb.Plugs.CachingBodyReader do
  @moduledoc """
  Body reader that caches the raw request body in `conn.assigns[:raw_body]`
  while still streaming it to `Plug.Parsers`. The Slack signature plug
  needs the verbatim body to compute the HMAC, but `Plug.Parsers` would
  otherwise consume it before we could read it.

  Wired into the endpoint via `body_reader:` on `Plug.Parsers`.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, cache(conn, body)}
      {:more, body, conn} -> {:more, body, cache(conn, body)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cache(conn, body) do
    update_in(conn.assigns[:raw_body], fn
      nil -> body
      existing -> [existing, body]
    end)
  end
end
