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

  @doc """
  Resolves the remote IP from a LiveView socket's `connect_info` map.

  The endpoint must include `:peer_data` and `:x_headers` in the live socket's
  `connect_info` for this to work. Returns `nil` when neither is available
  (e.g. during dead render).
  """
  def from_connect_info(%{x_headers: headers} = info) when is_list(headers) do
    case forwarded_for_header(headers) do
      nil -> peer_ip(info)
      ip -> ip
    end
  end

  def from_connect_info(%{peer_data: _} = info), do: peer_ip(info)
  def from_connect_info(_), do: nil

  defp forwarded_for_header(headers) do
    headers
    |> Enum.find(fn {name, _} -> String.downcase(name) == "x-forwarded-for" end)
    |> case do
      {_, value} ->
        value
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> List.first()

      _ ->
        nil
    end
  end

  defp peer_ip(%{peer_data: %{address: address}}) when not is_nil(address) do
    address |> :inet_parse.ntoa() |> to_string()
  end

  defp peer_ip(_), do: nil
end
