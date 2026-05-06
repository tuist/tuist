defmodule TuistWeb.AccountSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Kura
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "test-org",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "sets the right title", %{conn: conn, account: account} do
    # When
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    assert html =~ "Settings · #{account.name} · Tuist"
  end

  test "raises UnauthorizedError when the user is not authorized to update settings", %{
    conn: conn
  } do
    # Given
    organization =
      AccountsFixtures.organization_fixture(preload: [:account])

    user = AccountsFixtures.user_fixture()

    Accounts.add_user_to_organization(user, organization)

    conn = log_in_user(conn, user)

    # When / Then
    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      live(conn, ~p"/#{organization.account.name}/settings")
    end
  end

  test "displays the 'Rename organization' button when the selected account is an organization",
       %{
         conn: conn,
         account: account
       } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings")

    # Then
    assert has_element?(lv, "button", "Rename organization")
  end

  test "displays the 'Update username' button when the selected account is a user account",
       %{
         conn: conn,
         user: user
       } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{user.account.name}/settings")

    # Then
    assert has_element?(lv, "button", "Update username")
  end

  test "does not render Kura controls without the account feature flag", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    refute html =~ "Kura cache servers"
  end

  test "renders Kura controls when the account feature flag is enabled", %{conn: conn, account: account} do
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings")

    assert html =~ "Kura cache servers"
    assert has_element?(lv, "button", "Deploy Kura server")
  end

  test "shows Kura server state, machine, domain, and version", %{conn: conn, account: account} do
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.3", released_at: DateTime.utc_now(:second)}] end)

    {:ok, server} =
      Kura.create_server(%{
        account_id: account.id,
        region: "local",
        image_tag: "0.5.2"
      })

    {:ok, server} = Kura.activate_server(server, "0.5.2")

    stub(Kura, :list_nodes_for_server, fn account_id, server_id ->
      assert account_id == account.id
      assert server_id == server.id
      {:ok, [%{name: "kura-test-0", node_name: "kura-pool-1", ready: true}]}
    end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    assert html =~ "Active"
    assert html =~ "1/1 nodes ready"
    assert html =~ "kura-pool-1"
    assert html =~ server.url
    assert html =~ "0.5.2"
  end

  test "deploys a Kura server from account settings", %{conn: conn, account: account} do
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)
    account_id = account.id
    stub(Kura, :list_nodes_for_server, fn ^account_id, _server_id -> {:ok, []} end)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings")

    _html =
      lv
      |> form("#add-kura-server-form", server: %{region: "local"})
      |> render_submit()

    assert [%{region: "local", current_image_tag: nil}] = Kura.list_servers_for_account(account.id)
  end
end
