defmodule TuistWeb.Timezone do
  @moduledoc """
  Plug to extract user timezone from cookie and make it available to LiveViews.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    timezone =
      case Map.get(conn.req_cookies, "user_timezone") do
        nil -> nil
        timezone -> URI.decode(timezone)
      end

    conn
    |> put_session(:user_timezone, timezone)
  end
end
