defmodule Pulse.AuthTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Auth
  alias Pulse.Auth.Open
  alias Pulse.Auth.SharedSecret

  defp conn(headers \\ []) do
    Enum.reduce(headers, %Plug.Conn{}, fn {k, v}, c ->
      Plug.Conn.put_req_header(c, k, v)
    end)
  end

  describe "Pulse.Auth.module/0" do
    test "raises when nothing is configured — refuses to silently fail open" do
      Pulse.Runtime.delete_env(:pulse, Auth)
      # config.exs sets an explicit default. Reaching this branch means
      # someone deleted it; the correct response is a loud crash, not a
      # quiet accept-everything.
      assert_raise RuntimeError, ~r/Pulse.Auth is not configured/, fn ->
        Auth.module()
      end
    end

    test "raises when the prod sentinel is still in place" do
      Pulse.Runtime.put_env(:pulse, Auth, module: :must_configure_at_runtime)
      assert_raise RuntimeError, ~r/must_configure_at_runtime/, fn -> Auth.module() end
    end

    test "returns the configured module" do
      Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret)
      assert Auth.module() == SharedSecret
    end
  end

  describe "Pulse.Auth.Open" do
    test "accepts any tenant on any conn" do
      assert Open.verify(conn(), "acme") == :ok
      assert Open.verify(conn(), "") == :ok
    end
  end

  describe "Pulse.Auth.SharedSecret" do
    setup do
      token = "the-secret"
      hex = Base.encode16(:crypto.hash(:sha256, token), case: :lower)
      Pulse.Runtime.put_env(:pulse, Auth, tokens: %{"acme" => "sha256$#{hex}"})
      {:ok, token: token}
    end

    test "accepts the correct bearer token", %{token: token} do
      assert SharedSecret.verify(conn([{"authorization", "Bearer #{token}"}]), "acme") == :ok
    end

    test "accepts lowercase 'bearer' too", %{token: token} do
      assert SharedSecret.verify(conn([{"authorization", "bearer #{token}"}]), "acme") == :ok
    end

    test "rejects a wrong token with :invalid_token" do
      assert SharedSecret.verify(conn([{"authorization", "Bearer wrong"}]), "acme") ==
               {:error, :invalid_token}
    end

    test "rejects a missing header with :missing_token" do
      assert SharedSecret.verify(conn(), "acme") == {:error, :missing_token}
    end

    test "rejects an empty bearer with :missing_token" do
      assert SharedSecret.verify(conn([{"authorization", "Bearer "}]), "acme") ==
               {:error, :missing_token}
    end

    test "rejects a tenant with no configured token as :unknown_tenant", %{token: token} do
      assert SharedSecret.verify(conn([{"authorization", "Bearer #{token}"}]), "other") ==
               {:error, :unknown_tenant}
    end

    test "rejects a malformed stored value as :invalid_token" do
      Pulse.Runtime.put_env(:pulse, Auth, tokens: %{"acme" => "plaintext-not-hashed"})

      assert SharedSecret.verify(conn([{"authorization", "Bearer whatever"}]), "acme") ==
               {:error, :invalid_token}
    end

    test "accepts Basic credentials for the username's tenant", %{token: token} do
      basic = "Basic " <> Base.encode64("acme:#{token}")
      assert SharedSecret.verify(conn([{"authorization", basic}]), "acme") == :ok
      assert SharedSecret.verify(conn([{"authorization", "basic " <> Base.encode64("acme:#{token}")}]), "acme") == :ok
    end

    test "Basic credentials never authorize another tenant", %{token: token} do
      basic = "Basic " <> Base.encode64("acme:#{token}")
      assert SharedSecret.verify(conn([{"authorization", basic}]), "other") == {:error, :invalid_token}
    end

    test "rejects a wrong or malformed Basic password" do
      assert SharedSecret.verify(conn([{"authorization", "Basic " <> Base.encode64("acme:nope")}]), "acme") ==
               {:error, :invalid_token}

      for bad <- ["Basic !!!", "Basic " <> Base.encode64("acme"), "Basic " <> Base.encode64("acme:")] do
        assert SharedSecret.verify(conn([{"authorization", bad}]), "acme") == {:error, :missing_token}
      end
    end
  end

  describe "PulseWeb.BasicTenant" do
    test "names the Basic username as tenant only when no tenant header is present" do
      basic = {"authorization", "Basic " <> Base.encode64("acme:secret")}

      assert Plug.Conn.get_req_header(PulseWeb.BasicTenant.call(conn([basic]), []), "x-scope-orgid") == ["acme"]

      explicit = PulseWeb.BasicTenant.call(conn([basic, {"x-scope-orgid", "beta"}]), [])
      assert Plug.Conn.get_req_header(explicit, "x-scope-orgid") == ["beta"]

      bearer = PulseWeb.BasicTenant.call(conn([{"authorization", "Bearer x"}]), [])
      assert Plug.Conn.get_req_header(bearer, "x-scope-orgid") == []
    end
  end
end
