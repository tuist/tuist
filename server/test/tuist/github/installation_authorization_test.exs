defmodule Tuist.GitHub.InstallationAuthorizationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.GitHub.InstallationAuthorization

  @installation %{"id" => 123, "app_id" => 42, "account" => %{"type" => "Organization", "login" => "acme"}}

  setup do
    stub(Environment, :github_app_client_id, fn -> "client" end)
    stub(Environment, :github_app_client_secret, fn -> "secret" end)
    stub(Environment, :github_app_id, fn -> "42" end)

    stub(Req, :post, fn opts ->
      assert opts[:url] == "https://github.com/login/oauth/access_token"

      assert opts[:form] == [
               client_id: "client",
               client_secret: "secret",
               code: "code",
               redirect_uri: "https://tuist.test/callback"
             ]

      assert opts[:redirect] == false
      assert opts[:retry] == false
      assert opts[:receive_timeout] == 5000
      response(%{"access_token" => "user-token"})
    end)

    stub(Req, :get, fn opts ->
      assert {"authorization", "Bearer user-token"} in opts[:headers]
      assert opts[:redirect] == false
      assert opts[:retry] == false
      assert opts[:receive_timeout] == 5000

      case opts[:url] do
        "https://api.github.com/user/installations" -> response(%{"installations" => [@installation]})
        "https://api.github.com/user/memberships/orgs/acme" -> response(%{"state" => "active", "role" => "admin"})
      end
    end)

    :ok
  end

  test "exchanges the App code and verifies administration of the exact App installation" do
    assert :ok = verify()
  end

  test "repository access alone does not grant permission to bind an organization installation" do
    for membership <- [%{"state" => "active", "role" => "member"}, %{"state" => "pending", "role" => "admin"}] do
      stub(Req, :get, fn opts ->
        case opts[:url] do
          "https://api.github.com/user/installations" -> response(%{"installations" => [@installation]})
          "https://api.github.com/user/memberships/orgs/acme" -> response(membership)
        end
      end)

      assert {:error, :invalid_github_installation} = verify()
    end
  end

  test "personal installations require the same authenticated GitHub account" do
    for user_id <- [7, 8] do
      installation = Map.put(@installation, "account", %{"type" => "User", "id" => 7})

      stub(Req, :get, fn opts ->
        case opts[:url] do
          "https://api.github.com/user/installations" -> response(%{"installations" => [installation]})
          "https://api.github.com/user" -> response(%{"id" => user_id})
        end
      end)

      if user_id == 7, do: assert(:ok == verify()), else: assert({:error, :invalid_github_installation} == verify())
    end
  end

  test "rejects unrelated, suspended, and other App installations" do
    for installation <- [
          %{@installation | "id" => 456},
          %{@installation | "app_id" => 999},
          Map.put(@installation, "suspended_at", "2026-01-01T00:00:00Z"),
          Map.delete(@installation, "app_id")
        ] do
      stub(Req, :get, fn _ -> response(%{"installations" => [installation]}) end)
      assert {:error, :invalid_github_installation} = verify()
    end
  end

  test "checks subsequent pages without following provider-supplied URLs" do
    expect(Req, :get, fn opts ->
      assert opts[:params] == [per_page: 100, page: 1]
      response(%{"installations" => List.duplicate(%{"id" => 456, "app_id" => 42}, 100)})
    end)

    expect(Req, :get, fn opts ->
      assert opts[:url] == "https://api.github.com/user/installations"
      assert opts[:params] == [per_page: 100, page: 2]
      response(%{"installations" => [@installation]})
    end)

    expect(Req, :get, fn opts ->
      assert opts[:url] == "https://api.github.com/user/memberships/orgs/acme"
      response(%{"state" => "active", "role" => "admin"})
    end)

    assert :ok = verify()
  end

  test "bounds installation pagination to ten pages" do
    expect(Req, :get, 10, fn opts ->
      assert opts[:url] == "https://api.github.com/user/installations"
      assert opts[:params][:page] in 1..10
      assert opts[:receive_timeout] == 5000
      assert opts[:retry] == false
      response(%{"installations" => List.duplicate(%{"id" => 456, "app_id" => 42}, 100)})
    end)

    assert {:error, :invalid_github_installation} = verify()
  end

  test "fails closed on GitHub request timeouts" do
    stub(Req, :get, fn _ -> {:error, %Req.TransportError{reason: :timeout}} end)
    assert {:error, :invalid_github_installation} = verify()
  end

  test "rejects failed token exchanges without requesting installations" do
    stub(Req, :post, fn _ -> response(%{"error" => "bad_verification_code"}) end)
    reject(&Req.get/1)
    assert {:error, :invalid_github_installation} = verify()
  end

  test "fails closed when GitHub cannot verify installation access" do
    stub(Req, :get, fn _ -> {:ok, %Req.Response{status: 403, body: %{}}} end)
    assert {:error, :invalid_github_installation} = verify()
  end

  defp verify, do: InstallationAuthorization.verify("code", "123", "https://tuist.test/callback")
  defp response(body), do: {:ok, %Req.Response{status: 200, body: body}}
end
