defmodule TuistWeb.GitHubAppManifestControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures
  alias TuistWeb.Errors.BadRequestError

  describe "GET /integrations/github/manifest/start" do
    test "renders an auto-submit form pointing at the GHES /settings/apps/new", %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      ghes_url = "https://github.example.com"
      state_token = VCS.generate_github_state_token(account.id, ghes_url)

      conn = get(conn, ~p"/integrations/github/manifest/start", %{"state" => state_token})

      assert conn.status == 200
      body = response(conn, 200)
      assert body =~ "#{ghes_url}/settings/apps/new"
      assert body =~ "name=\"manifest\""
      assert body =~ "document.getElementById('manifest-form').submit()"
    end

    test "scopes the CSP so the inline submit and cross-origin form action are allowed", %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      ghes_url = "https://github.example.com"
      state_token = VCS.generate_github_state_token(account.id, ghes_url)

      conn = get(conn, ~p"/integrations/github/manifest/start", %{"state" => state_token})

      [csp] = get_resp_header(conn, "content-security-policy")
      body = response(conn, 200)

      # The form posts cross-origin to the GHES instance; without an
      # explicit form-action allowance the browser would block it.
      assert csp =~ "form-action 'self' #{ghes_url}"

      # The submit script must carry the nonce that the page-scoped CSP
      # advertises, otherwise the browser silently drops it and the
      # customer never reaches GHES.
      assert [_, nonce] = Regex.run(~r/'nonce-([^']+)'/, csp)
      assert body =~ ~s(<script nonce="#{nonce}">)
    end

    test "rejects missing state", %{conn: conn} do
      assert_raise BadRequestError, fn ->
        get(conn, ~p"/integrations/github/manifest/start")
      end
    end

    test "rejects state targeting github.com", %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      state_token = VCS.generate_github_state_token(account.id, "https://github.com")

      assert_raise BadRequestError, fn ->
        get(conn, ~p"/integrations/github/manifest/start", %{"state" => state_token})
      end
    end

    test "rejects an invalid state token", %{conn: conn} do
      assert_raise BadRequestError, fn ->
        get(conn, ~p"/integrations/github/manifest/start", %{"state" => "garbage"})
      end
    end
  end

  describe "GET /integrations/github/manifest/callback" do
    test "exchanges the manifest code, persists App credentials, and redirects to install", %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      ghes_url = "https://github.example.com"
      state_token = VCS.generate_github_state_token(account.id, ghes_url)
      manifest_code = "tmpcode"

      app_payload = %{
        "id" => 42,
        "slug" => "tuist-on-ghes",
        "client_id" => "Iv1.abc",
        "client_secret" => "shhh",
        "pem" => "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        "webhook_secret" => "wh-secret"
      }

      stub(SSRFGuard, :pin, fn url ->
        assert url == "#{ghes_url}/api/v3/app-manifests/#{manifest_code}/conversions"
        {:ok, "https://198.51.100.10/api/v3/app-manifests/#{manifest_code}/conversions", "github.example.com"}
      end)

      stub(SSRFGuard, :connect_options, fn "github.example.com" -> [hostname: "github.example.com"] end)

      stub(Req, :post, fn _opts -> {:ok, %Req.Response{status: 201, body: app_payload}} end)

      conn =
        get(conn, ~p"/integrations/github/manifest/callback", %{
          "code" => manifest_code,
          "state" => state_token
        })

      assert redirected_to(conn) =~ "#{ghes_url}/apps/tuist-on-ghes/installations/new?state="

      {:ok, installation} = VCS.get_github_app_installation_for_account(account.id)
      assert installation.client_url == ghes_url
      assert installation.app_id == "42"
      assert installation.app_slug == "tuist-on-ghes"
      assert installation.client_id == "Iv1.abc"
      assert installation.client_secret == "shhh"
      assert installation.private_key =~ "BEGIN RSA"
      assert installation.webhook_secret == "wh-secret"
      assert is_nil(installation.installation_id)
    end

    test "rejects an invalid state token", %{conn: conn} do
      assert_raise BadRequestError, fn ->
        get(conn, ~p"/integrations/github/manifest/callback", %{"code" => "x", "state" => "garbage"})
      end
    end

    test "refuses to overwrite an account that already has a working installation", %{conn: conn} do
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      ghes_url = "https://github.example.com"
      state_token = VCS.generate_github_state_token(account.id, ghes_url)

      VCSFixtures.github_app_installation_fixture(
        account_id: account.id,
        installation_id: "existing-install-id"
      )

      stub(SSRFGuard, :pin, fn _url -> {:ok, "https://198.51.100.10/path", "github.example.com"} end)
      stub(SSRFGuard, :connect_options, fn _ -> [] end)

      stub(Req, :post, fn _opts ->
        {:ok,
         %Req.Response{
           status: 201,
           body: %{
             "id" => 99,
             "slug" => "duplicate",
             "client_id" => "Iv1.dup",
             "client_secret" => "dup-secret",
             "pem" => "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
             "webhook_secret" => "dup-wh"
           }
         }}
      end)

      assert_raise BadRequestError, ~r/Uninstall it before registering a new one/, fn ->
        get(conn, ~p"/integrations/github/manifest/callback", %{
          "code" => "tmpcode",
          "state" => state_token
        })
      end

      # The original installation must still be there, untouched.
      {:ok, installation} = VCS.get_github_app_installation_for_account(account.id)
      assert installation.installation_id == "existing-install-id"
      assert is_nil(installation.app_id)
    end
  end
end
