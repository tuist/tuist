defmodule TuistOps.JIT.TailscaleClientTest do
  @moduledoc """
  Exercises `user_role/1` via the public API by mocking the HTTP
  layer (Req). The role-string → atom mapping is the key contract
  here: every Policy decision and every kubectl impersonation call
  reads through it, and the catch-all default must be `:unknown`
  (not `:member`, which silently grants non-prod self-approval +
  view-tier kubectl to an unenumerated identity tier — the P4
  regression door).
  """

  use ExUnit.Case, async: false
  use Mimic

  alias TuistOps.Environment
  alias TuistOps.JIT.TailscaleClient

  setup :verify_on_exit!

  setup do
    stub(Environment, :tailscale_client_id, fn -> "client-id" end)
    stub(Environment, :tailscale_client_secret, fn -> "client-secret" end)
    # OAuth token request — always succeeds with a canned token.
    stub(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 200, body: %{"access_token" => "tok", "expires_in" => 3600}}}
    end)

    :ok
  end

  # Each test uses a unique tailnet to bypass the persistent_term
  # users-list cache (cache key includes tailnet). list_users/1
  # takes a :tailnet option; user_role/1 doesn't, so we exercise
  # parse_role/1 indirectly by stubbing Req.get to return the role
  # under test against the default tailnet.
  defp stub_users(role_string) do
    expect(Req, :get, fn _url, _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "users" => [%{"loginName" => "marek@tuist.dev", "role" => role_string}]
         }
       }}
    end)
  end

  defp clear_user_cache do
    :persistent_term.erase({TuistOps.JIT.TailscaleClient, :users})
  rescue
    ArgumentError -> :ok
  end

  setup do
    clear_user_cache()
    :ok
  end

  describe "user_role/1 — canonical role mappings" do
    @canonical [
      {"owner", :owner},
      {"admin", :admin},
      {"network-admin", :network_admin},
      {"it-admin", :it_admin},
      {"auditor", :auditor},
      {"billing-admin", :billing_admin},
      {"member", :member}
    ]

    for {input, expected} <- @canonical do
      test "#{inspect(input)} → #{inspect(expected)}" do
        stub_users(unquote(input))
        assert TailscaleClient.user_role("marek@tuist.dev") == {:ok, unquote(expected)}
      end
    end
  end

  describe "user_role/1 — unknown role contract (P4)" do
    test "unrecognised role string → :unknown, not :member" do
      stub_users("super-admin")

      assert TailscaleClient.user_role("marek@tuist.dev") == {:ok, :unknown},
             "regression: an unknown role mapped to :member would silently grant non-prod self-approval"
    end

    test "empty role string → :unknown" do
      stub_users("")
      assert TailscaleClient.user_role("marek@tuist.dev") == {:ok, :unknown}
    end

    test "case-sensitive: \"Owner\" (not \"owner\") → :unknown" do
      stub_users("Owner")
      assert TailscaleClient.user_role("marek@tuist.dev") == {:ok, :unknown}
    end

    test "nil role → :unknown" do
      stub_users(nil)
      assert TailscaleClient.user_role("marek@tuist.dev") == {:ok, :unknown}
    end
  end

  describe "user_role/1 — identity not on tailnet" do
    test "email absent from users list → {:error, :not_found}" do
      expect(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"users" => [%{"loginName" => "someone-else@tuist.dev", "role" => "owner"}]}
         }}
      end)

      assert TailscaleClient.user_role("ghost@tuist.dev") == {:error, :not_found}
    end

    test "non-binary input → {:error, :not_found}" do
      assert TailscaleClient.user_role(nil) == {:error, :not_found}
      assert TailscaleClient.user_role(123) == {:error, :not_found}
    end
  end

  describe "user_role/1 — failure modes" do
    test "Tailscale users endpoint non-200 → {:error, _}" do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: "boom"}}
      end)

      assert {:error, {:list_users_failed, 500, _}} =
               TailscaleClient.user_role("marek@tuist.dev")
    end

    test "HTTP transport error → {:error, _}" do
      expect(Req, :get, fn _url, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, {:list_users_error, _}} = TailscaleClient.user_role("marek@tuist.dev")
    end
  end
end
