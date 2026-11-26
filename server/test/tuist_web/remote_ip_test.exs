defmodule TuistWeb.RemoteIpTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  describe "get/1" do
    test "prefers the Cloudflare connecting IP header" do
      # Given
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("cf-connecting-ip", " 203.0.113.10 ")
        |> Plug.Conn.put_req_header("x-forwarded-for", "spoofed-ip, 173.245.48.10")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "203.0.113.10"
    end

    test "prefers the Cloudflare header when directly connected to a Cloudflare IPv6 address" do
      # Given
      conn =
        build_conn()
        |> Map.put(:remote_ip, {0x2606, 0x4700, 0, 0, 0, 0, 0, 1})
        |> Plug.Conn.put_req_header("cf-connecting-ip", "2001:db8::1")
        |> Plug.Conn.put_req_header("x-forwarded-for", "spoofed-ip")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "2001:db8::1"
    end

    test "ignores the forwarding headers of a public peer" do
      # Given
      conn =
        build_conn()
        |> Map.put(:remote_ip, {203, 0, 113, 20})
        |> Plug.Conn.put_req_header("cf-connecting-ip", "198.51.100.10")
        |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.11, 198.51.100.20")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "203.0.113.20"
    end

    test "takes the address the ingress recorded for a request that skipped Cloudflare" do
      # Given: the headers the production ingress forwards (use-forwarded-headers
      # on, PROXY protocol) for a client at 198.18.0.50 that connects to the
      # origin directly and writes its own X-Forwarded-For and CF-Connecting-IP.
      conn =
        build_conn()
        |> Map.put(:remote_ip, {0, 0, 0, 0, 0, 0xFFFF, 0x0A00, 0x0105})
        |> Plug.Conn.put_req_header("cf-connecting-ip", "6.6.6.6")
        |> Plug.Conn.put_req_header("x-forwarded-for", "6.6.6.6, 198.18.0.50")
        |> Plug.Conn.put_req_header("x-tuist-edge-address", "198.18.0.50")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "198.18.0.50"
    end

    test "skips private addresses a client prepends to the forwarding chain" do
      # Given
      conn =
        build_conn()
        |> Map.put(:remote_ip, {10, 0, 1, 5})
        |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.7, 10.9.9.9, 198.18.0.50, 10.0.0.9")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "198.18.0.50"
    end

    test "takes the furthest address of a chain that stayed on private networks" do
      # Given
      conn =
        build_conn()
        |> Map.put(:remote_ip, {10, 0, 1, 5})
        |> Plug.Conn.put_req_header("x-forwarded-for", "192.168.1.5, 10.0.0.9")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "192.168.1.5"
    end

    test "reads forwarding entries that carry the client's port" do
      # Given: what Azure Application Gateway forwards by default
      conn =
        build_conn()
        |> Map.put(:remote_ip, {10, 0, 1, 5})
        |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.7, 203.0.113.7:51234, 10.0.0.9:443")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "203.0.113.7"
    end

    test "reads bracketed IPv6 forwarding entries with and without a port" do
      # Given
      with_port =
        build_conn()
        |> Map.put(:remote_ip, {10, 0, 1, 5})
        |> Plug.Conn.put_req_header("x-forwarded-for", "[2001:db8::7]:51234")

      bare =
        build_conn()
        |> Map.put(:remote_ip, {10, 0, 1, 5})
        |> Plug.Conn.put_req_header("x-forwarded-for", "2001:db8::8")

      # When / Then
      assert TuistWeb.RemoteIp.get(with_port) == "2001:db8::7"
      assert TuistWeb.RemoteIp.get(bare) == "2001:db8::8"
    end

    test "falls back to the Cloudflare edge when a trusted hop sends no valid client address" do
      # Given
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("cf-connecting-ip", "not-an-ip")
        |> Plug.Conn.put_req_header("x-forwarded-for", "198.51.100.7, 173.245.48.10")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "173.245.48.10"
    end

    test "ignores empty forwarding headers" do
      # Given
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("cf-connecting-ip", "  ")
        |> Plug.Conn.put_req_header("x-forwarded-for", " , 198.51.100.7")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "198.51.100.7"
    end

    test "gets the connection address when forwarding headers are not present" do
      # Given
      conn = build_conn()

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "127.0.0.1"
    end
  end

  describe "origin/1" do
    test "reads the country the edge resolved" do
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "FR"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "FR"
    end

    test "narrows to a subdivision in the countries holding more than one region" do
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "US"}, {"cf-region-code", "OR"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "US-OR"
    end

    test "keeps the country when the subdivision header is absent" do
      # The subdivision rides a managed transform rather than the default
      # header set, so an unconfigured zone must answer coarsely, not wrongly.
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "US"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "US"
    end

    test "ignores a subdivision for a country that has only one region" do
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "FR"}, {"cf-region-code", "IDF"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "FR"
    end

    test "says which fix an unattributed request needs" do
      # The two are indistinguishable from outside the request, and they need
      # different fixes: one is the zone's headers, the other is the hop list.
      untrusted =
        build_conn()
        |> Map.put(:remote_ip, {203, 0, 113, 20})
        |> Plug.Conn.put_req_header("cf-ipcountry", "FR")

      # Bandit listening on `::` reports IPv4 peers as IPv4-mapped IPv6, so this
      # is the shape the ingress hop actually arrives in. Classifying it as
      # written makes a private peer read as public and refuses every request.
      v4_mapped_peer =
        build_conn()
        |> Map.put(:remote_ip, {0, 0, 0, 0, 0, 0xFFFF, 0xC0A8, 0x06FC})
        |> Plug.Conn.put_req_header("x-forwarded-for", "89.24.10.5, 162.159.121.29")
        |> Plug.Conn.put_req_header("cf-ipcountry", "CZ")

      assert TuistWeb.RemoteIp.attributed_origin(v4_mapped_peer) == {:ok, "CZ"}

      # A mapped *public* address is still public; unmapping must not launder it.
      v4_mapped_public =
        build_conn()
        |> Map.put(:remote_ip, {0, 0, 0, 0, 0, 0xFFFF, 0x1758, 0x2C94})
        |> Plug.Conn.put_req_header("x-forwarded-for", "89.24.10.5, 162.159.121.29")
        |> Plug.Conn.put_req_header("cf-ipcountry", "CZ")

      assert TuistWeb.RemoteIp.attributed_origin(v4_mapped_public) ==
               {:error, :location_from_untrusted_hop}

      # The forwarded chain ends at our own load balancer rather than the edge,
      # so the edge address arrives in its own header. Trusted only from a
      # private peer: nginx overwrites any inbound value, so a client that
      # reaches the origin directly cannot assert one, and its own address is
      # public and fails the peer check.
      via_edge_header =
        build_conn()
        |> Map.put(:remote_ip, {192, 168, 6, 220})
        |> Plug.Conn.put_req_header("x-forwarded-for", "89.24.10.5, 10.0.0.7")
        |> Plug.Conn.put_req_header("x-tuist-edge-address", "141.101.68.26")
        |> Plug.Conn.put_req_header("cf-ipcountry", "CZ")

      assert TuistWeb.RemoteIp.attributed_origin(via_edge_header) == {:ok, "CZ"}

      forged_edge_header =
        build_conn()
        |> Map.put(:remote_ip, {203, 0, 113, 20})
        |> Plug.Conn.put_req_header("x-tuist-edge-address", "141.101.68.26")
        |> Plug.Conn.put_req_header("cf-ipcountry", "CZ")

      assert TuistWeb.RemoteIp.attributed_origin(forged_edge_header) ==
               {:error, :location_from_untrusted_hop}

      bare = Map.put(build_conn(), :remote_ip, {203, 0, 113, 20})

      # A location present but disbelieved says the zone is configured and the
      # hop list is not; neither says the zone is.
      assert TuistWeb.RemoteIp.attributed_origin(untrusted) == {:error, :location_from_untrusted_hop}
      assert TuistWeb.RemoteIp.attributed_origin(bare) == {:error, :untrusted_hop}
      assert TuistWeb.RemoteIp.attributed_origin(cloudflare_conn([])) == {:error, :no_location}
      assert TuistWeb.RemoteIp.attributed_origin(cloudflare_conn([{"cf-ipcountry", "FR"}])) == {:ok, "FR"}
    end

    test "answers nothing for an untrusted hop" do
      # The header is trivially forgeable, so an account could otherwise vote
      # itself into a region by setting it.
      # Given
      conn =
        build_conn()
        |> Map.put(:remote_ip, {203, 0, 113, 20})
        |> Plug.Conn.put_req_header("cf-ipcountry", "FR")

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == nil
    end

    test "answers nothing when the edge could not place the address" do
      for country <- ["XX", "T1", "", "not-a-country"] do
        conn = cloudflare_conn([{"cf-ipcountry", country}])

        assert TuistWeb.RemoteIp.origin(conn) == nil
      end
    end

    test "answers nothing when the edge sent no country at all" do
      # Given
      conn = cloudflare_conn([])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == nil
    end

    test "rejects a malformed subdivision rather than carrying it into a label" do
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "US"}, {"cf-region-code", "not a code"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "US"
    end
  end

  # A private peer whose last forwarded hop is Cloudflare, which is the trusted
  # shape `get/1` already establishes.
  defp cloudflare_conn(headers) do
    conn = Plug.Conn.put_req_header(build_conn(), "x-forwarded-for", "203.0.113.10, 173.245.48.10")

    Enum.reduce(headers, conn, fn {name, value}, conn ->
      Plug.Conn.put_req_header(conn, name, value)
    end)
  end
end
