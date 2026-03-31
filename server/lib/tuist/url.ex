defmodule Tuist.URL do
  @moduledoc ~S"""
  URL validation utilities including SSRF protection.
  """

  def public_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, query: nil, fragment: nil}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        not private_host?(host)

      _ ->
        false
    end
  end

  def public_url?(_), do: false

  defp private_host?(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, ip} ->
        private_ip?(ip)

      {:error, _} ->
        private_hostname?(host) or resolves_to_private_ip?(charlist)
    end
  end

  defp resolves_to_private_ip?(charlist) do
    resolves_to_private_ipv4?(charlist) or resolves_to_private_ipv6?(charlist)
  end

  defp resolves_to_private_ipv4?(charlist) do
    case :inet.getaddr(charlist, :inet) do
      {:ok, ip} -> private_ip?(ip)
      {:error, _} -> false
    end
  end

  defp resolves_to_private_ipv6?(charlist) do
    case :inet.getaddr(charlist, :inet6) do
      {:ok, ip} -> private_ip?(ip)
      {:error, _} -> false
    end
  end

  # IPv4 private/reserved ranges
  defp private_ip?({127, _, _, _}), do: true
  defp private_ip?({10, _, _, _}), do: true
  defp private_ip?({172, second, _, _}) when second >= 16 and second <= 31, do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?({0, 0, 0, 0}), do: true
  defp private_ip?({169, 254, _, _}), do: true
  defp private_ip?({100, second, _, _}) when second >= 64 and second <= 127, do: true
  defp private_ip?({198, second, _, _}) when second >= 18 and second <= 19, do: true

  # IPv6 private/reserved ranges
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp private_ip?({first, _, _, _, _, _, _, _}) when first >= 0xFC00 and first <= 0xFDFF, do: true
  defp private_ip?({0xFE80, _, _, _, _, _, _, _}), do: true

  defp private_ip?(_), do: false

  defp private_hostname?(host) do
    downcased = String.downcase(host)

    downcased == "localhost" or
      String.ends_with?(downcased, ".localhost") or
      String.ends_with?(downcased, ".local") or
      String.ends_with?(downcased, ".internal")
  end
end
