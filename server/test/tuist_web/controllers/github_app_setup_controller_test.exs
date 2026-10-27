defmodule TuistWeb.GitHubAppSetupControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.GitHub.InstallationAuthorization
  alias Tuist.VCS
  alias Tuist.VCS.GitHubAppInstallation
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures
  alias TuistWeb.Errors.BadRequestError

  setup :register_and_log_in_user

  setup do
    stub(Environment, :github_app_client_id, fn -> "app-client" end)
    stub(InstallationAuthorization, :verify, fn _, _, _ -> :ok end)
    :ok
  end

  test "Tuist-initiated setup connects the selected account with global credentials", %{conn: conn, user: user} do
    state = VCS.generate_github_state_token(user.account.id)
    conn = conn |> get(~p"/integrations/github/setup", installation_id: "12345", state: state) |> complete_authorization()
    assert get_session(conn, :integration_installation) == nil
    assert redirected_to(conn) == "/#{user.account.name}/settings/integrations"
    {:ok, installation} = VCS.get_github_app_installation_for_account(user.account.id)
    assert installation.installation_id == "12345"
    assert installation.client_url == "https://github.com"
    assert is_nil(installation.app_id)
    assert is_nil(installation.client_id)
    assert is_nil(installation.client_secret)
    assert is_nil(installation.private_key)
    assert is_nil(installation.webhook_secret)
    refute GitHubAppInstallation.enterprise?(installation)
    refute GitHubAppInstallation.per_installation_credentials?(installation)
  end

  test "reinstalling for the same account is idempotent", %{conn: conn, user: user} do
    existing = VCSFixtures.github_app_installation_fixture(account_id: user.account.id, installation_id: "12345")
    state = VCS.generate_github_state_token(user.account.id)
    conn |> get(~p"/integrations/github/setup", installation_id: "12345", state: state) |> complete_authorization()
    {:ok, installation} = VCS.get_github_app_installation_for_account(user.account.id)
    assert installation.id == existing.id
  end

  test "fills installation_id on a pending GHES row and preserves credentials", %{conn: conn, user: user} do
    host = "https://github.example.com"

    VCSFixtures.github_app_installation_fixture(
      account_id: user.account.id,
      installation_id: nil,
      client_url: host,
      app_id: "999",
      app_slug: "tuist-on-ghes",
      client_id: "Iv1.x",
      client_secret: "csec",
      private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
      webhook_secret: "wh"
    )

    state = VCS.generate_github_state_token(user.account.id, host)
    conn = get(conn, ~p"/integrations/github/setup", installation_id: "67890", state: state)
    assert redirected_to(conn) == "/#{user.account.name}/settings/integrations"
    {:ok, installation} = VCS.get_github_app_installation_for_account(user.account.id)
    assert installation.installation_id == "67890"
    assert installation.client_url == host
    assert installation.app_id == "999"
    assert installation.private_key =~ "BEGIN RSA"
  end

  test "rejects GHES setup without a pending registration for that host", %{conn: conn, user: user} do
    state = VCS.generate_github_state_token(user.account.id, "https://github.example.com")

    assert_raise BadRequestError, ~r/registration flow first/, fn ->
      get(conn, ~p"/integrations/github/setup", installation_id: "67890", state: state)
    end

    assert {:error, :not_found} = VCS.get_github_app_installation_for_account(user.account.id)
  end

  test "rejects cross-host setup without changing the existing registration", %{conn: conn, user: user} do
    VCSFixtures.github_app_installation_fixture(
      account_id: user.account.id,
      installation_id: nil,
      client_url: "https://ghes-b.example.com",
      app_id: "999",
      app_slug: "tuist-on-ghes-b",
      client_id: "Iv1.b",
      client_secret: "csec-b",
      private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
      webhook_secret: "wh-b"
    )

    for host <- ["https://ghes-a.example.com", "https://github.com"] do
      state = VCS.generate_github_state_token(user.account.id, host)

      assert_raise BadRequestError, ~r/different GitHub host/, fn ->
        conn = get(conn, ~p"/integrations/github/setup", installation_id: "67890", state: state)
        if host == "https://github.com", do: complete_authorization(conn)
      end
    end

    {:ok, installation} = VCS.get_github_app_installation_for_account(user.account.id)
    assert is_nil(installation.installation_id)
    assert installation.client_url == "https://ghes-b.example.com"
  end

  test "cannot transfer an installation from another account", %{conn: conn, user: user} do
    other = AccountsFixtures.account_fixture()
    VCSFixtures.github_app_installation_fixture(account_id: other.id, installation_id: "12345")
    state = VCS.generate_github_state_token(user.account.id)

    assert_raise BadRequestError, "This GitHub app installation is already connected.", fn ->
      conn |> get(~p"/integrations/github/setup", installation_id: "12345", state: state) |> complete_authorization()
    end
  end

  test "a valid state does not grant administration of someone else's account", %{conn: conn} do
    other = AccountsFixtures.account_fixture()
    state = VCS.generate_github_state_token(other.id)

    assert_raise BadRequestError, fn ->
      get(conn, ~p"/integrations/github/setup", installation_id: "12345", state: state)
    end

    assert {:error, :not_found} = VCS.get_github_app_installation_for_account(other.id)
  end

  test "rejects missing installation IDs and invalid state", %{conn: conn} do
    assert_raise BadRequestError, fn -> get(conn, ~p"/integrations/github/setup", state: "bad") end

    assert_raise BadRequestError, fn ->
      get(conn, ~p"/integrations/github/setup", installation_id: "12345", state: "bad")
    end
  end

  test "provider-initiated setup verifies GitHub access before organization selection", %{conn: conn, user: user} do
    stub(Environment, :github_app_client_id, fn -> "app-client" end)
    conn = get(conn, ~p"/integrations/github/setup", installation_id: "12345")
    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    pending = get_session(conn, :github_installation_authorization)
    assert query["client_id"] == "app-client"
    assert query["state"] == pending.state
    assert pending.user_id == user.id
    assert {:error, :not_found} = VCS.get_github_app_installation_for_account(user.account.id)

    expect(InstallationAuthorization, :verify, fn "code", "12345", callback ->
      assert String.ends_with?(callback, "/integrations/github/authorize")
      :ok
    end)

    conn = get(recycle(conn), ~p"/integrations/github/authorize", code: "code", state: pending.state)
    assert redirected_to(conn) == "/integrations/installation"
    assert get_session(conn, :github_installation_authorization) == nil
    assert %{provider: :github, proof: "12345", user_id: user_id} = get_session(conn, :integration_installation)
    assert user_id == user.id
  end

  test "authorization rejects mismatched state, expired requests and different users before exchanging codes", %{
    conn: conn,
    user: user
  } do
    reject(&InstallationAuthorization.verify/3)

    for {state, user_id, issued_at} <- [
          {"other-state", user.id, System.system_time(:second)},
          {"state", user.id, System.system_time(:second) - 601},
          {"state", user.id + 1, System.system_time(:second)}
        ] do
      conn =
        put_session(conn, :github_installation_authorization, %{
          state: state,
          user_id: user_id,
          issued_at: issued_at,
          installation_id: "12345"
        })

      assert_raise BadRequestError, fn ->
        get(conn, ~p"/integrations/github/authorize", code: "code", state: "state")
      end
    end
  end

  test "authorization rejects a user without access to the installation", %{conn: conn, user: user} do
    conn =
      put_session(conn, :github_installation_authorization, %{
        state: "state",
        user_id: user.id,
        issued_at: System.system_time(:second),
        installation_id: "12345"
      })

    expect(InstallationAuthorization, :verify, fn _, _, _ -> {:error, :invalid_github_installation} end)

    assert_raise BadRequestError, fn ->
      get(conn, ~p"/integrations/github/authorize", code: "code", state: "state")
    end
  end

  test "signed-out installers return to setup after login" do
    conn = get(build_conn(), ~p"/integrations/github/setup", installation_id: "12345")
    assert redirected_to(conn) == "/users/log_in"
    assert get_session(conn, :user_return_to) == "/integrations/github/setup?installation_id=12345"
  end

  defp complete_authorization(conn) do
    pending = get_session(conn, :github_installation_authorization)
    get(recycle(conn), ~p"/integrations/github/authorize", code: "code", state: pending.state)
  end
end
