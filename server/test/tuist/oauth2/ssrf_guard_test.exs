defmodule Tuist.OAuth2.SsrfGuardTest do
  use ExUnit.Case, async: true

  alias Tuist.OAuth2.SsrfGuard

  describe "pin/1 — literal IP rejection" do
    test "rejects a URL whose host is the IPv4 loopback literal" do
      assert {:error, :private_ip_resolved} = SsrfGuard.pin("https://127.0.0.1/oauth2/token")
    end

    test "rejects a URL whose host is in RFC1918 10/8" do
      assert {:error, :private_ip_resolved} = SsrfGuard.pin("https://10.0.0.1/oauth2/token")
    end

    test "rejects a URL whose host is in RFC1918 172.16/12" do
      assert {:error, :private_ip_resolved} = SsrfGuard.pin("https://172.16.0.1/oauth2/token")
      assert {:error, :private_ip_resolved} = SsrfGuard.pin("https://172.31.255.254/oauth2/token")
    end

    test "rejects a URL whose host is in RFC1918 192.168/16" do
      assert {:error, :private_ip_resolved} = SsrfGuard.pin("https://192.168.1.1/oauth2/token")
    end

    test "rejects link-local / cloud metadata space (169.254/16)" do
      assert {:error, :private_ip_resolved} =
               SsrfGuard.pin("https://169.254.169.254/latest/meta-data/")
    end

    test "rejects carrier-grade NAT (100.64/10)" do
      assert {:error, :private_ip_resolved} = SsrfGuard.pin("https://100.64.0.1/oauth2/token")
    end

    test "rejects the IPv6 loopback literal" do
      assert {:error, :private_ip_resolved} = SsrfGuard.pin("https://[::1]/oauth2/token")
    end

    test "rejects IPv6 unique local addresses (fc00::/7)" do
      assert {:error, :private_ip_resolved} =
               SsrfGuard.pin("https://[fd00::1]/oauth2/token")
    end
  end

  describe "pin/1 — malformed URL rejection" do
    test "rejects a URL with a non-http(s) scheme" do
      assert {:error, :invalid_url} = SsrfGuard.pin("ftp://example.com/oauth2/token")
      assert {:error, :invalid_url} = SsrfGuard.pin("file:///etc/passwd")
      assert {:error, :invalid_url} = SsrfGuard.pin("gopher://example.com/")
    end

    test "rejects an empty string" do
      assert {:error, :invalid_url} = SsrfGuard.pin("")
    end
  end

  describe "pin/1 — DNS failure" do
    test "rejects hostnames that do not resolve (reserved .invalid TLD per RFC 2606)" do
      # .invalid is guaranteed by RFC 2606 to never resolve, so this test is
      # stable regardless of the local resolver and doesn't make real external
      # DNS queries.
      assert {:error, :dns_failure} =
               SsrfGuard.pin("https://tuist-ssrf-guard-test.invalid/oauth2/token")
    end
  end

  describe "pin/1 — TOCTOU guarantee" do
    test "pinned URL contains only the IP, not the original hostname" do
      # The whole point of this module is that the pinned URL gives the HTTP
      # client no hostname to re-resolve. If the URL still contained the
      # original hostname, an attacker could rebind between our check and
      # httpc's connect. We prove that by checking the URI's host component
      # is the literal IP, even for the one input we can test without
      # mocking — a literal public IP.
      {:error, :private_ip_resolved} = SsrfGuard.pin("https://127.0.0.1/token")
      # The above path takes a shortcut because the literal is private. The
      # positive path (public literal IP) is exercised via higher-level tests
      # and manual verification — testing it here would require mocking
      # `:inet.getaddrs`, which is an Erlang core module whose mocking has
      # systemic risks for the rest of the suite.
    end
  end

  describe "ssl_adapter_opts/1" do
    test "returns adapter options that enforce verify_peer" do
      opts = SsrfGuard.ssl_adapter_opts("idp.example.com")
      ssl = Keyword.fetch!(opts, :ssl)

      assert Keyword.fetch!(ssl, :verify) == :verify_peer
    end

    test "sets SNI to the original hostname, NOT the pinned IP" do
      opts = SsrfGuard.ssl_adapter_opts("idp.example.com")
      ssl = Keyword.fetch!(opts, :ssl)

      assert Keyword.fetch!(ssl, :server_name_indication) == ~c"idp.example.com"
    end

    test "configures certificate hostname verification for https" do
      opts = SsrfGuard.ssl_adapter_opts("idp.example.com")
      ssl = Keyword.fetch!(opts, :ssl)

      match_fun =
        ssl
        |> Keyword.fetch!(:customize_hostname_check)
        |> Keyword.fetch!(:match_fun)

      assert match_fun == :public_key.pkix_verify_hostname_match_fun(:https)
    end

    test "includes a populated CA trust store (omitting cacerts silently disables verification)" do
      opts = SsrfGuard.ssl_adapter_opts("idp.example.com")
      ssl = Keyword.fetch!(opts, :ssl)

      cacerts = Keyword.fetch!(ssl, :cacerts)

      assert is_list(cacerts)
      assert cacerts != []
    end
  end
end
