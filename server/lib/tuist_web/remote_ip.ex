defmodule TuistWeb.RemoteIp do
  @moduledoc """
  A module that provides functions for getting the remote IP address.

  Originally taken from: https://websymphony.net/blog/how-to-get-remote-ip-from-x-forwarded-for-in-phoenix/

  Cloudflare ranges mirror https://www.cloudflare.com/ips/ so the connecting header is only
  accepted from Cloudflare or from the trusted private ingress directly behind it.
  """

  import Bitwise

  @cloudflare_ranges [
    {{173, 245, 48, 0}, 20},
    {{103, 21, 244, 0}, 22},
    {{103, 22, 200, 0}, 22},
    {{103, 31, 4, 0}, 22},
    {{141, 101, 64, 0}, 18},
    {{108, 162, 192, 0}, 18},
    {{190, 93, 240, 0}, 20},
    {{188, 114, 96, 0}, 20},
    {{197, 234, 240, 0}, 22},
    {{198, 41, 128, 0}, 17},
    {{162, 158, 0, 0}, 15},
    {{104, 16, 0, 0}, 13},
    {{104, 24, 0, 0}, 14},
    {{172, 64, 0, 0}, 13},
    {{131, 0, 72, 0}, 22},
    {{0x2400, 0xCB00, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2606, 0x4700, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2803, 0xF800, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2405, 0xB500, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2405, 0x8100, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2A06, 0x98C0, 0, 0, 0, 0, 0, 0}, 29},
    {{0x2C0F, 0xF248, 0, 0, 0, 0, 0, 0}, 32}
  ]

  def get(conn) do
    forwarded_for = header(conn, "x-forwarded-for")
    cloudflare_ip = cloudflare_ip(conn, forwarded_for)
    forwarded_ip = first_forwarded_ip(forwarded_for)

    cloudflare_ip || forwarded_ip || format_ip(conn.remote_ip)
  end

  defp cloudflare_ip(conn, forwarded_for) do
    with value when not is_nil(value) <- header(conn, "cf-connecting-ip"),
         {:ok, address} <- parse_address(value),
         true <- trusted_cloudflare_hop?(conn.remote_ip, forwarded_for) do
      format_ip(address)
    else
      _ -> nil
    end
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
    |> forwarded_ips()
    |> List.first()
  end

  defp trusted_cloudflare_hop?(peer_address, forwarded_for) do
    cloudflare_address?(peer_address) or
      (private_address?(peer_address) and cloudflare_address?(last_forwarded_ip(forwarded_for)))
  end

  defp last_forwarded_ip(nil), do: nil
  defp last_forwarded_ip(forwarded_for), do: forwarded_for |> forwarded_ips() |> List.last()

  defp forwarded_ips(forwarded_for) do
    forwarded_for
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_address(value), do: :inet.parse_address(String.to_charlist(value))

  defp cloudflare_address?(nil), do: false

  defp cloudflare_address?(address) when is_binary(address) do
    case parse_address(address) do
      {:ok, parsed_address} -> cloudflare_address?(parsed_address)
      {:error, _reason} -> false
    end
  end

  defp cloudflare_address?(address) do
    Enum.any?(@cloudflare_ranges, &address_in_range?(address, &1))
  end

  defp address_in_range?(address, {network, prefix}) do
    with {address_integer, bits} <- address_to_integer(address),
         {network_integer, ^bits} <- address_to_integer(network) do
      address_integer >>> (bits - prefix) == network_integer >>> (bits - prefix)
    else
      _ -> false
    end
  end

  defp address_to_integer(address) when tuple_size(address) == 4 do
    integer = Enum.reduce(Tuple.to_list(address), 0, fn octet, acc -> acc <<< 8 ||| octet end)
    {integer, 32}
  end

  defp address_to_integer(address) when tuple_size(address) == 8 do
    integer = Enum.reduce(Tuple.to_list(address), 0, fn segment, acc -> acc <<< 16 ||| segment end)
    {integer, 128}
  end

  defp address_to_integer(_address), do: :error

  defp private_address?({10, _, _, _}), do: true
  defp private_address?({127, _, _, _}), do: true
  defp private_address?({169, 254, _, _}), do: true
  defp private_address?({172, second, _, _}) when second in 16..31, do: true
  defp private_address?({192, 168, _, _}), do: true
  defp private_address?({100, second, _, _}) when second in 64..127, do: true
  defp private_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_address?({first, _, _, _, _, _, _, _}) when first in 0xFC00..0xFDFF, do: true
  defp private_address?({first, _, _, _, _, _, _, _}) when first in 0xFE80..0xFEBF, do: true
  defp private_address?(_address), do: false

  defp format_ip(ip), do: ip |> :inet_parse.ntoa() |> to_string()
end
