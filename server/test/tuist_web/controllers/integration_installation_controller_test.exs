defmodule TuistWeb.IntegrationInstallationControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Origin
  alias Tuist.Origin.Client
  alias Tuist.Origin.Signatures
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures
  alias TuistWeb.Errors.BadRequestError

  setup :register_and_log_in_user

  setup %{conn: conn, user: user} do
    pending = %{provider: :github, proof: "12345", user_id: user.id, issued_at: System.system_time(:second)}
    %{conn: put_session(conn, :integration_installation, pending), pending: pending}
  end

  test "uses the auth frame and lists only administrable organizations and the personal account", %{
    conn: conn,
    user: user
  } do
    admin = AccountsFixtures.organization_fixture(creator: user, name: "admin-org")
    member = AccountsFixtures.organization_fixture(name: "member-org")
    Accounts.add_user_to_organization(user, member)
    foreign = AccountsFixtures.organization_fixture(name: "foreign-org")

    conn = get(conn, ~p"/integrations/installation")
    html = html_response(conn, 200)
    assert html =~ ~s(id="integration-installation")
    assert html =~ "Choose an organization"
    assert html =~ "GitHub"
    assert html =~ admin.account.name
    assert html =~ user.account.name
    refute html =~ member.account.name
    refute html =~ foreign.account.name
    refute html =~ ~s(name="installation_id")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "connects GitHub to the selected organization and consumes the pending installation", %{conn: conn, user: user} do
    org = AccountsFixtures.organization_fixture(creator: user)
    conn = post(conn, ~p"/integrations/installation", account_id: to_string(org.account.id))
    assert redirected_to(conn) == "/#{org.account.name}/settings/integrations"
    assert get_session(conn, :integration_installation) == nil
    assert {:ok, %{installation_id: "12345"}} = VCS.get_github_app_installation_for_account(org.account.id)
    assert {:error, :not_found} = VCS.get_github_app_installation_for_account(user.account.id)
  end

  test "explains host conflicts without modifying an existing GHES registration", %{conn: conn, user: user} do
    existing =
      VCSFixtures.github_app_installation_fixture(
        account_id: user.account.id,
        installation_id: nil,
        client_url: "https://github.example.com",
        private_key: "pending-ghes-private-key"
      )

    assert_raise BadRequestError, ~r/different GitHub host/, fn ->
      post(conn, ~p"/integrations/installation", account_id: to_string(user.account.id))
    end

    assert {:ok, installation} = VCS.get_github_app_installation_for_account(user.account.id)
    assert installation.id == existing.id
    assert installation.client_url == existing.client_url
    assert installation.private_key == existing.private_key
    assert is_nil(installation.installation_id)
  end

  test "Origin revalidates its signed receipt and fetches the current installation before connecting", %{
    conn: conn,
    user: user,
    pending: pending
  } do
    stub(Environment, :origin_app_id, fn -> "app_tuist" end)
    pending = %{pending | provider: :origin, proof: "receipt"}
    conn = put_session(conn, :integration_installation, pending)

    expect(Signatures, :verify_receipt, fn "receipt", nil ->
      {:ok, %{"sub" => "i_verified", "namespace_id" => "ns_test"}}
    end)

    expect(Client, :get_installation, fn "i_verified" ->
      {:ok,
       %{"id" => "i_verified", "appId" => "app_tuist", "target" => %{"id" => "ns_test"}, "scopes" => Client.scopes()}}
    end)

    conn = post(conn, ~p"/integrations/installation", account_id: to_string(user.account.id))
    assert redirected_to(conn) == "/#{user.account.name}/settings/integrations"
    assert [%{installation_id: "i_verified"}] = Origin.list_installations(user.account.id)
    assert get_session(conn, :integration_installation) == nil
  end

  test "rejects expired Origin receipts at submission", %{conn: conn, user: user, pending: pending} do
    conn = put_session(conn, :integration_installation, %{pending | provider: :origin, proof: "expired"})
    expect(Signatures, :verify_receipt, fn "expired", nil -> {:error, :invalid_origin_receipt} end)
    reject(&Client.get_installation/1)

    assert_raise BadRequestError, fn ->
      post(conn, ~p"/integrations/installation", account_id: to_string(user.account.id))
    end
  end

  test "rechecks administration on submission and rejects forged account IDs", %{conn: conn, user: user} do
    org = AccountsFixtures.organization_fixture()
    Accounts.add_user_to_organization(user, org)

    for account_id <- [to_string(org.account.id), "not-an-id", "999999999"] do
      assert_raise BadRequestError, fn ->
        post(conn, ~p"/integrations/installation", account_id: account_id)
      end
    end

    assert {:error, :not_found} = VCS.get_github_app_installation_for_account(org.account.id)
  end

  test "does not transfer installations already attached to another account", %{conn: conn, user: user} do
    other = AccountsFixtures.account_fixture()
    VCSFixtures.github_app_installation_fixture(account_id: other.id, installation_id: "12345")

    assert_raise BadRequestError, fn ->
      post(conn, ~p"/integrations/installation", account_id: to_string(user.account.id))
    end

    assert {:ok, %{account_id: account_id}} = VCS.get_github_app_installation_for_account(other.id)
    assert account_id == other.id
  end

  test "missing, expired, or another user's pending installation is rejected", %{conn: conn, user: user, pending: pending} do
    for invalid <- [nil, %{pending | issued_at: System.system_time(:second) - 601}, %{pending | user_id: user.id + 1}] do
      conn = put_session(conn, :integration_installation, invalid)
      assert_raise BadRequestError, fn -> get(conn, ~p"/integrations/installation") end

      assert_raise BadRequestError, fn ->
        post(conn, ~p"/integrations/installation", account_id: to_string(user.account.id))
      end
    end
  end

  test "cancel discards the pending installation without linking it", %{conn: conn, user: user} do
    conn = delete(conn, ~p"/integrations/installation")
    assert redirected_to(conn) == "/dashboard"
    assert get_session(conn, :integration_installation) == nil
    assert {:error, :not_found} = VCS.get_github_app_installation_for_account(user.account.id)
  end
end
