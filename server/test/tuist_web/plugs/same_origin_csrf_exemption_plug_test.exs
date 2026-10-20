defmodule TuistWeb.Plugs.SameOriginCSRFExemptionPlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TuistWeb.Plugs.SameOriginCSRFExemptionPlug

  defp call(headers) do
    conn =
      Enum.reduce(headers, conn(:post, "/newsletter"), fn {name, value}, conn -> put_req_header(conn, name, value) end)

    SameOriginCSRFExemptionPlug.call(conn, SameOriginCSRFExemptionPlug.init([]))
  end

  test "exempts a request whose fetch metadata is same-origin" do
    assert call([{"sec-fetch-site", "same-origin"}]).private[:plug_skip_csrf_protection] == true
  end

  test "exempts a request whose origin equals the request origin" do
    assert call([{"origin", "http://www.example.com"}]).private[:plug_skip_csrf_protection] == true
  end

  test "matches the origin against the origin forwarded by the proxy" do
    headers = [
      {"x-forwarded-proto", "https"},
      {"x-forwarded-host", "tuist.dev"},
      {"origin", "https://tuist.dev"}
    ]

    assert call(headers).private[:plug_skip_csrf_protection] == true
  end

  test "leaves every other request to the CSRF token check" do
    for headers <- [
          [],
          [{"origin", "https://evil.example"}],
          [{"origin", "http://www.example.com:3000"}],
          [{"origin", "http://www.example.com"}, {"x-forwarded-host", "tuist.dev"}],
          [{"sec-fetch-site", "cross-site"}],
          [{"sec-fetch-site", "same-site"}, {"origin", "http://www.example.com"}],
          [{"sec-fetch-site", "none"}]
        ] do
      refute Map.has_key?(call(headers).private, :plug_skip_csrf_protection)
    end
  end
end
