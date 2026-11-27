defmodule LuftServer.HTTP.SSRFGuard do
  @moduledoc ~S"""
  Resolves a URL's hostname to an IP, rejects it if any resolved address is
  non-public, and returns a "pinned" URL that uses the validated IP directly —
  along with the HTTPS options needed to keep TLS working against the
  original hostname.

  Why a separate pin-at-request-time step instead of just a preflight check:
  a one-off preflight validates a hostname's current DNS result but the
  actual HTTP client (`:httpc`) will resolve DNS again when it connects. An
  attacker-controlled IdP can answer with a public IP during validation and
  rebind to loopback (`127.0.0.0/8`), RFC1918 space (`10/8`, `172.16/12`,
  `192.168/16`), link-local (`169.254/16` — AWS/GCP metadata), carrier-grade
  NAT, etc. by the time the request fires. Connect-time enforcement requires
  that the HTTP client connects to the exact address we validated.

  The trick: resolve once, rewrite the URL so the `host` component is the
  literal IP, add a `Host:` header with the original hostname so the
  upstream load balancer still routes correctly, and configure SSL options
  with `server_name_indication` + a hostname match function so SNI and
  certificate validation continue to use the original hostname. No second
  DNS lookup happens — the URL already contains the IP.

  IPv6: handled via `:inet.getaddrs/2` with `:inet6`. IPv6 hosts are wrapped
  in brackets when rewritten to match `https://[::1]/path` URI syntax.
  """

  @doc """
  Resolves `url`'s hostname, validates every resolved address is public, and
  returns `{:ok, pinned_url, original_hostname}` on success or
  `{:error, reason}` on failure.
  """
  def pin(url) do
    with %URI{scheme: scheme, host: host} = uri
         when scheme in ["http", "https"] and is_binary(host) and host != "" <-
           URI.parse(url),
         {:ok, ip} <- resolve_to_public_ip(host) do
      {:ok, URI.to_string(%{uri | host: encode_ip(ip)}), host}
    else
      %URI{} -> {:error, :invalid_url}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns Req/Finch/Mint `connect_options` that keep TLS working when the
  URL's host component is a raw IP (from `pin/1`) instead of the original
  hostname.

  The `:hostname` key tells Mint to use the original hostname for SNI and
  the `Host:` header. The `:transport_opts` configure peer verification
  against the original hostname's certificate chain.
  """
  def connect_options(hostname) do
    [
      hostname: hostname,
      transport_opts: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(hostname),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]
  end

  defp resolve_to_public_ip(host) do
    host_chars = String.to_charlist(host)

    ipv4 = getaddrs(host_chars, :inet)
    ipv6 = getaddrs(host_chars, :inet6)
    all = ipv4 ++ ipv6

    cond do
      all == [] ->
        {:error, :dns_failure}

      not Enum.all?(all, &public_ip?/1) ->
        {:error, :private_ip_resolved}

      true ->
        {:ok, List.first(all)}
    end
  end

  defp getaddrs(host_chars, family) do
    case :inet.getaddrs(host_chars, family) do
      {:ok, ips} -> ips
      {:error, _} -> []
    end
  end

  # `URI.to_string/1` encloses IPv6 hosts in brackets itself (RFC 3986
  # §3.2.2), so the host is the bare address for both families.
  defp encode_ip(ip), do: ip |> :inet.ntoa() |> to_string()

  defp public_ip?(ip), do: not private_ip?(ip)

  defp private_ip?({127, _, _, _}), do: true
  defp private_ip?({10, _, _, _}), do: true
  defp private_ip?({172, second, _, _}) when second >= 16 and second <= 31, do: true
  defp private_ip?({192, 168, _, _}), do: true
  defp private_ip?({0, _, _, _}), do: true
  defp private_ip?({first, _, _, _}) when first >= 224, do: true
  defp private_ip?({169, 254, _, _}), do: true
  defp private_ip?({100, second, _, _}) when second >= 64 and second <= 127, do: true
  defp private_ip?({198, second, _, _}) when second >= 18 and second <= 19, do: true
  # IETF protocol assignments (RFC 6890), including NAT64/DS-Lite special-use addresses.
  defp private_ip?({192, 0, 0, _}), do: true

  # IPv6 private/reserved ranges
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp private_ip?({0, 0, 0, 0, 0, 0, 0, 0}), do: true

  defp private_ip?({first, _, _, _, _, _, _, _}) when first >= 0xFC00 and first <= 0xFDFF,
    do: true

  defp private_ip?({first, _, _, _, _, _, _, _}) when first >= 0xFE80 and first <= 0xFEFF,
    do: true

  defp private_ip?({first, _, _, _, _, _, _, _}) when first >= 0xFF00, do: true

  # Embedded IPv4 must keep its original network classification.
  defp private_ip?({0, 0, 0, 0, 0, 0xFFFF, high, low}), do: private_embedded_ipv4?(high, low)
  defp private_ip?({0, 0, 0, 0, 0, 0, high, low}), do: private_embedded_ipv4?(high, low)
  defp private_ip?({0x64, 0xFF9B, 0, 0, 0, 0, high, low}), do: private_embedded_ipv4?(high, low)
  defp private_ip?({0x64, 0xFF9B, 1, _, _, _, _, _}), do: true
  # 6to4 (RFC 3056) carries the IPv4 address in its second and third groups.
  defp private_ip?({0x2002, high, low, _, _, _, _, _}), do: private_embedded_ipv4?(high, low)
  # Teredo (RFC 4380) obfuscates the client's IPv4 address; reject the prefix.
  defp private_ip?({0x2001, 0, _, _, _, _, _, _}), do: true

  defp private_ip?(_), do: false

  defp private_embedded_ipv4?(high, low) do
    private_ip?({div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)})
  end
end
