defmodule TuistWeb.Plugs.TimezonePlug do
  @moduledoc """
  Plug to extract user timezone from cookie and make it available to LiveViews.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    timezone = timezone(conn)

    # A late response must not rewrite an unchanged snapshot of the cookie
    # session over a login or return destination written by another tab.
    if get_session(conn, :user_timezone) == timezone do
      conn
    else
      put_session(conn, :user_timezone, timezone)
    end
  end

  # The cookie is client-controlled and the session is a cookie capped at
  # 4096 bytes, so only a known timezone name is copied into it.
  defp timezone(conn) do
    with timezone when is_binary(timezone) <- Map.get(conn.req_cookies, "user_timezone"),
         timezone = URI.decode(timezone),
         true <- Timex.is_valid_timezone?(timezone) do
      timezone
    else
      _ -> nil
    end
  end
end
