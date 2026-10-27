defmodule Atlas.URL do
  @moduledoc """
  URL validation shared across tools that fetch or render external URLs.

  `validate_public/1` enforces the SSRF guards used by every outbound
  request the agent makes: http/https only, standard web ports, no
  credentials, no private or link-local hosts, and no IPv6 literals in
  reserved ranges. Tools should call this before handing a URL off to
  Req, BrowseChrome, or any other network client.
  """

  @blocked_hosts MapSet.new([
                   "localhost",
                   "metadata.google.internal"
                 ])

  @blocked_host_suffixes [
    ".internal",
    ".lan",
    ".local",
    ".localhost"
  ]

  @doc """
  Parses `url` and verifies it points at a public http or https host.
  """
  def validate_public(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, "Only http and https URLs are supported."}

      not is_binary(uri.host) or uri.host == "" ->
        {:error, "The URL must include a hostname."}

      uri.userinfo not in [nil, ""] ->
        {:error, "Credentials in URLs are not supported."}

      not allowed_port?(uri) ->
        {:error, "Only standard web ports are supported."}

      not public_host?(uri.host) ->
        {:error, "This URL points to a local or private network host, which Atlas will not fetch."}

      true ->
        {:ok, uri}
    end
  end

  def validate_public(_url), do: {:error, "Provide a valid http or https URL."}

  defp allowed_port?(%URI{port: nil}), do: true
  defp allowed_port?(%URI{scheme: "http", port: 80}), do: true
  defp allowed_port?(%URI{scheme: "https", port: 443}), do: true
  defp allowed_port?(_uri), do: false

  defp public_host?(host) when is_binary(host) do
    normalized_host = host |> String.trim() |> String.trim_trailing(".") |> String.downcase()

    cond do
      normalized_host == "" ->
        false

      MapSet.member?(@blocked_hosts, normalized_host) ->
        false

      Enum.any?(@blocked_host_suffixes, &String.ends_with?(normalized_host, &1)) ->
        false

      String.contains?(normalized_host, "..") ->
        false

      true ->
        case :inet.parse_address(String.to_charlist(normalized_host)) do
          {:ok, ip} -> public_ip_literal?(ip)
          {:error, :einval} -> String.contains?(normalized_host, ".")
        end
    end
  end

  defp public_ip_literal?({10, _, _, _}), do: false
  defp public_ip_literal?({100, second, _, _}) when second in 64..127, do: false
  defp public_ip_literal?({127, _, _, _}), do: false
  defp public_ip_literal?({169, 254, _, _}), do: false
  defp public_ip_literal?({172, second, _, _}) when second in 16..31, do: false
  defp public_ip_literal?({192, 0, 0, _}), do: false
  defp public_ip_literal?({192, 0, 2, _}), do: false
  defp public_ip_literal?({192, 168, _, _}), do: false
  defp public_ip_literal?({198, 18, _, _}), do: false
  defp public_ip_literal?({198, 19, _, _}), do: false
  defp public_ip_literal?({198, 51, 100, _}), do: false
  defp public_ip_literal?({203, 0, 113, _}), do: false
  defp public_ip_literal?({224, _, _, _}), do: false
  defp public_ip_literal?({255, 255, 255, 255}), do: false
  defp public_ip_literal?({0, _, _, _}), do: false

  defp public_ip_literal?({0, 0, 0, 0, 0, 0, 0, 0}), do: false
  defp public_ip_literal?({0, 0, 0, 0, 0, 0, 0, 1}), do: false
  defp public_ip_literal?({0, 0, 0, 0, 0, 65_535, _, _}), do: false
  defp public_ip_literal?({8_193, 3_512, _, _, _, _, _, _}), do: false
  defp public_ip_literal?({first, _, _, _, _, _, _, _}) when first in 64_512..64_767, do: false
  defp public_ip_literal?({first, _, _, _, _, _, _, _}) when first in 65_152..65_535, do: false
  defp public_ip_literal?({first, _, _, _, _, _, _, _}) when first >= 65_280, do: false
  defp public_ip_literal?({_a, _b, _c, _d}), do: true
  defp public_ip_literal?({_a, _b, _c, _d, _e, _f, _g, _h}), do: true
end
