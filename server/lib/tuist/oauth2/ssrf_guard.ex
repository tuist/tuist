defmodule Tuist.OAuth2.SsrfGuard do
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

  alias Tuist.URL

  @doc """
  Resolves `url`'s hostname, validates every resolved address is public, and
  returns `{:ok, pinned_url, original_hostname}` on success or
  `{:error, reason}` on failure.
  """
  def pin(url) do
    with %URI{scheme: scheme, host: host} = uri when scheme in ["http", "https"] and is_binary(host) and host != "" <-
           URI.parse(url),
         {:ok, ip} <- resolve_to_public_ip(host) do
      {:ok, URI.to_string(%{uri | host: encode_ip(ip)}), host}
    else
      %URI{} -> {:error, :invalid_url}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_url}
    end
  end

  @doc """
  Returns the adapter options that need to be passed to the OAuth2/Tesla
  client so that TLS handshake, SNI, and certificate verification continue
  to use the original hostname (even though the TCP connection is opened
  against a raw IP). Without these, connecting to an IP breaks SNI and the
  server either serves the wrong certificate or rejects the handshake.
  """
  def ssl_adapter_opts(hostname) do
    [
      ssl: [
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

      not Enum.all?(all, &URL.public_ip?/1) ->
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

  defp encode_ip({_, _, _, _} = ipv4), do: ipv4 |> :inet.ntoa() |> to_string()

  defp encode_ip({_, _, _, _, _, _, _, _} = ipv6) do
    # URI spec §3.2.2: IPv6 literals in URLs must be enclosed in brackets.
    "[" <> (ipv6 |> :inet.ntoa() |> to_string()) <> "]"
  end
end
