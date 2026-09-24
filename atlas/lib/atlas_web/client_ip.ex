defmodule AtlasWeb.ClientIP do
  @moduledoc """
  Resolves the caller's address for requests that arrive through a proxy.

  Never trust the left-most `X-Forwarded-For` entry. A proxy appends to that
  header, so the left-most value is whatever the client sent, which makes it
  useless for anything a caller wants to evade, such as a rate limit.

  The order here is deliberate:

    * `CF-Connecting-IP`, which Cloudflare sets and overwrites, so a client
      cannot forge it through Cloudflare. Atlas does not sit behind Cloudflare
      today; this is here so that putting it in front starts working rather
      than silently keeping the wrong value.
    * the right-most `X-Forwarded-For` entry, which is the address the closest
      proxy observed rather than anything the client supplied. The ingress runs
      with `use-forwarded-headers` off, so it replaces the header with the
      single address it saw.
    * the peer address, when no proxy header is present at all.

  Note that the ingress load balancer currently hides the caller: it does not
  speak the PROXY protocol and the service uses `externalTrafficPolicy:
  Cluster`, so every request arrives with the balancer's own address. Until
  that changes, treat the result as "the caller as far as we can tell", which
  may be shared by everyone.
  """

  def get(conn) do
    resolve(conn.req_headers, conn.remote_ip)
  end

  def from_connect_info(%{x_headers: headers, peer_data: %{address: peer_address}}) when is_list(headers) do
    resolve(headers, peer_address)
  end

  def from_connect_info(%{x_headers: headers}) when is_list(headers) do
    resolve(headers, nil)
  end

  def from_connect_info(%{peer_data: %{address: peer_address}}) do
    resolve([], peer_address)
  end

  def from_connect_info(_connect_info), do: "unknown"

  defp resolve(headers, peer_address) do
    cloudflare(headers) || forwarded_for(headers) || peer(peer_address)
  end

  defp cloudflare(headers) do
    headers |> header("cf-connecting-ip") |> List.first() |> present()
  end

  defp forwarded_for(headers) do
    headers
    |> header("x-forwarded-for")
    |> List.last()
    |> case do
      value when is_binary(value) -> value |> String.split(",") |> List.last() |> present()
      nil -> nil
    end
  end

  defp header(headers, name), do: for({^name, value} <- headers, do: value)

  defp peer(address) when is_tuple(address), do: address |> :inet.ntoa() |> to_string()
  defp peer(_address), do: "unknown"

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil
end
