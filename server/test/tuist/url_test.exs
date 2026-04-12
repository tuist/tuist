defmodule Tuist.URLTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.URL

  describe "public_url?/1" do
    test "accepts valid public URLs" do
      assert URL.public_url?("https://auth.example.com/authorize")
      assert URL.public_url?("https://login.okta.com/oauth2/token")
    end

    test "accepts http URLs in dev and test environments" do
      assert URL.public_url?("http://sso.company.org/userinfo")
    end

    test "rejects http URLs outside of dev and test environments" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)

      refute URL.public_url?("http://sso.company.org/userinfo")
      assert URL.public_url?("https://sso.company.org/userinfo")
    end

    test "rejects non-URL values" do
      refute URL.public_url?("not-a-url")
      refute URL.public_url?("")
      refute URL.public_url?(nil)
      refute URL.public_url?("ftp://example.com")
    end

    test "rejects URLs with query strings or fragments" do
      refute URL.public_url?("https://example.com?foo=bar")
      refute URL.public_url?("https://example.com#section")
    end

    test "rejects localhost" do
      refute URL.public_url?("https://localhost/authorize")
      refute URL.public_url?("https://LOCALHOST/authorize")
    end

    test "rejects .localhost subdomains" do
      refute URL.public_url?("https://app.localhost/authorize")
    end

    test "rejects .local hostnames" do
      refute URL.public_url?("https://service.local/authorize")
    end

    test "rejects .internal hostnames" do
      refute URL.public_url?("https://metadata.internal/authorize")
    end

    test "rejects loopback IPs" do
      refute URL.public_url?("https://127.0.0.1/authorize")
      refute URL.public_url?("https://127.255.255.255/authorize")
    end

    test "rejects private class A IPs (10.x.x.x)" do
      refute URL.public_url?("https://10.0.0.1/authorize")
    end

    test "rejects private class B IPs (172.16-31.x.x)" do
      refute URL.public_url?("https://172.16.0.1/authorize")
      refute URL.public_url?("https://172.31.255.255/authorize")
    end

    test "rejects private class C IPs (192.168.x.x)" do
      refute URL.public_url?("https://192.168.1.1/authorize")
    end

    test "rejects link-local IPs (169.254.x.x)" do
      refute URL.public_url?("https://169.254.169.254/authorize")
    end

    test "rejects carrier-grade NAT IPs (100.64-127.x.x)" do
      refute URL.public_url?("https://100.64.0.1/authorize")
      refute URL.public_url?("https://100.127.255.255/authorize")
    end

    test "rejects benchmark testing IPs (198.18-19.x.x)" do
      refute URL.public_url?("https://198.18.0.1/authorize")
      refute URL.public_url?("https://198.19.255.255/authorize")
    end

    test "rejects unspecified address" do
      refute URL.public_url?("https://0.0.0.0/authorize")
    end
  end
end
