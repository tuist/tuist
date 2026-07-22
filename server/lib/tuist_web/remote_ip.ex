defmodule TuistWeb.RemoteIp do
  @moduledoc """
  A module that provides functions for getting the remote IP address.

  Originally taken from: https://websymphony.net/blog/how-to-get-remote-ip-from-x-forwarded-for-in-phoenix/
  """

  def get(conn) do
    cloudflare_ip = header(conn, "cf-connecting-ip")
    forwarded_ip = conn |> header("x-forwarded-for") |> first_forwarded_ip()

    cloudflare_ip || forwarded_ip || format_ip(conn.remote_ip)
  end

  defp header(conn, name) do
    conn
    |> Plug.Conn.get_req_header(name)
    |> Enum.find_value(fn value ->
      case String.trim(value) do
        "" -> nil
        value -> value
      end
    end)
  end

  defp first_forwarded_ip(nil), do: nil

  defp first_forwarded_ip(forwarded_for) do
    forwarded_for
    |> String.split(",")
    |> Enum.find_value(fn value ->
      case String.trim(value) do
        "" -> nil
        value -> value
      end
    end)
  end

  defp format_ip(ip), do: ip |> :inet_parse.ntoa() |> to_string()
end
