defmodule AtlasWeb.ClientIPTest do
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 3]

  alias AtlasWeb.ClientIP

  defp request(headers, peer \\ {203, 0, 113, 9}) do
    Enum.reduce(headers, %{conn(:post, "/", "") | remote_ip: peer}, fn {k, v}, acc ->
      Plug.Conn.put_req_header(acc, k, v)
    end)
  end

  test "falls back to the peer address when no proxy header is present" do
    assert ClientIP.get(request([])) == "203.0.113.9"
  end

  test "uses the address the closest proxy observed, not the one the client claimed" do
    # A caller who sends their own X-Forwarded-For gets it appended to, so the
    # left-most entry is attacker-controlled and must not be what we limit on.
    assert ClientIP.get(request([{"x-forwarded-for", "1.2.3.4, 198.51.100.7"}])) == "198.51.100.7"
  end

  test "ignores a forged chain entirely when Cloudflare reports the caller" do
    headers = [{"x-forwarded-for", "1.2.3.4"}, {"cf-connecting-ip", "198.51.100.23"}]

    assert ClientIP.get(request(headers)) == "198.51.100.23"
  end

  test "handles a single-entry forwarded header, which is what the ingress sets" do
    assert ClientIP.get(request([{"x-forwarded-for", "198.51.100.42"}])) == "198.51.100.42"
  end

  test "falls through a blank header rather than returning an empty key" do
    assert ClientIP.get(request([{"x-forwarded-for", "   "}])) == "203.0.113.9"
  end

  test "uses the ingress-provided address passed through a LiveView socket" do
    connect_info = %{
      x_headers: [{"x-forwarded-for", "1.2.3.4, 198.51.100.7"}],
      peer_data: %{address: {10, 0, 0, 1}}
    }

    assert ClientIP.from_connect_info(connect_info) == "198.51.100.7"
  end
end
