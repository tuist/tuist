defmodule TuistWeb.RemoteIp do
  @moduledoc """
  A module that provides functions for getting the remote IP address.

  Originally taken from: https://websymphony.net/blog/how-to-get-remote-ip-from-x-forwarded-for-in-phoenix/
  """

  def get(conn) do
    forwarded_for =
      conn
      |> Plug.Conn.get_req_header("x-forwarded-for")
      |> List.first()

    if forwarded_for do
      forwarded_for
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> List.first()
    else
      conn.remote_ip
      |> :inet_parse.ntoa()
      |> to_string()
    end
  end
end
