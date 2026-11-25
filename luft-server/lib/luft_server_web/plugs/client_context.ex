defmodule LuftServerWeb.Plugs.ClientContext do
  @moduledoc """
  Puts where a request came from in its Logger metadata, so every line it
  logs, request lines and `LuftServer.AuthEvents` alike, can be attributed.

  Cloudflare fronts the origin and names the client in `CF-Connecting-IP`;
  the peer itself is the cluster's ingress. That header, like
  `X-Forwarded-For`, is only as trustworthy as the hop that set it, so the
  forwarded chain is logged too, for checking which hops a request took.
  """

  @max_header_bytes 256

  def init(opts), do: opts

  def call(conn, _opts) do
    Logger.metadata(
      client_address: client_address(conn),
      forwarded_for: header(conn, "x-forwarded-for", ~r/[\x00-\x20\x7f]/),
      user_agent: header(conn, "user-agent")
    )

    conn
  end

  defp client_address(conn) do
    with value when is_binary(value) <- header(conn, "cf-connecting-ip"),
         {:ok, address} <- :inet.parse_strict_address(String.to_charlist(value)) do
      to_string(:inet.ntoa(address))
    else
      _ -> to_string(:inet.ntoa(conn.remote_ip))
    end
  end

  # Bounded, and without control characters, so a header cannot forge or
  # split log lines. The forwarded chain also loses its spaces, which would
  # end its logfmt value at the first hop.
  defp header(conn, name, strip \\ ~r/[\x00-\x1f\x7f]/) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] ->
        value
        |> binary_part(0, min(byte_size(value), @max_header_bytes))
        |> String.replace(strip, "")

      [] ->
        nil
    end
  end
end
