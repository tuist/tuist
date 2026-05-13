defmodule TuistWeb.AccountSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Environment
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

  test "allows ops users to access settings for any account", %{conn: conn} do
    organization =
      AccountsFixtures.organization_fixture(preload: [:account])

    user = AccountsFixtures.user_fixture()
    stub(Environment, :ops_user_handles, fn -> [user.account.name] end)

    conn = log_in_user(conn, user)

    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings")

    assert html =~ "Settings · #{organization.account.name} · Tuist"
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

  test "does not render Kura controls when the account does not have Kura enabled", %{conn: conn, account: account} do
    stub(Environment, :ops_user_handles, fn -> [] end)
    stub(Environment, :dev?, fn -> false end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    refute html =~ "Kura cache servers"
  end

  test "renders Kura controls for Kura-enabled accounts", %{conn: conn, account: account} do
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Environment, :dev?, fn -> false end)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings")

    assert html =~ "Kura cache servers"
    assert html =~ "Local Controller (kind)"
    refute html =~ "Local (kind)"
    refute html =~ "No Kura servers"
    assert has_element?(lv, "button", "Deploy Kura server")
    assert html =~ "create_kura_server"
    assert html =~ ~s(phx-value-region="local-controller")
    assert has_element?(lv, "#kura-servers-table")
    assert html =~ "Not deployed"
  end

  test "shows Kura server state, domain, and version", %{conn: conn, user: user, account: account} do
    enable_ops_for(user)
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Environment, :dev?, fn -> false end)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.3", released_at: DateTime.utc_now(:second)}] end)

    {:ok, server} =
      Kura.create_server(%{
        account_id: account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = hd(server.deployments)
    {:ok, deployment} = Kura.mark_running(deployment)
    {:ok, _deployment} = Kura.mark_succeeded(deployment)

    {:ok, server} = Kura.activate_server(server, "0.5.2")

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    assert html =~ "Active"
    assert html =~ server.url
    assert html =~ "0.5.2"
    refute html =~ "kura@0.5.2"
  end

  test "allows adding another managed Kura region when one is already deployed", %{
    conn: conn,
    user: user,
    account: account
  } do
    enable_ops_for(user)
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> ["eu-central", "us-east", "us-west"] end)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "kura@0.5.2", image_tag: "0.5.2", released_at: nil}] end)

    {:ok, _server} =
      Kura.create_server(%{
        account_id: account.id,
        region: "eu-central",
        image_tag: "0.5.2"
      })

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings")

    assert html =~ "EU Central"
    refute html =~ "Hetzner"
    assert html =~ "US East"
    assert html =~ "US West"
    assert html =~ "Not deployed"
    assert html =~ ~s(phx-value-region="us-east")
    assert html =~ ~s(phx-value-region="us-west")
    assert has_element?(lv, "button", "Deploy Kura server")
  end

  test "keeps an active Kura server active during an in-flight deployment", %{conn: conn, user: user, account: account} do
    enable_ops_for(user)
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Environment, :dev?, fn -> false end)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.3", released_at: DateTime.utc_now(:second)}] end)

    {:ok, server} =
      Kura.create_server(%{
        account_id: account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = hd(server.deployments)
    {:ok, deployment} = Kura.mark_running(deployment)
    {:ok, _deployment} = Kura.mark_succeeded(deployment)

    {:ok, server} = Kura.activate_server(server, "0.5.2")
    {:ok, _deployment} = Kura.create_deployment(server, "0.5.3")

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    assert html =~ "Active"
    refute html =~ "Deploying"
  end

  test "deploys a Kura server from account settings", %{conn: conn, user: user, account: account} do
    enable_ops_for(user)
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Environment, :dev?, fn -> false end)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings")

    stub(Kura, :latest_versions, fn 1 ->
      raise "create_kura_server should reuse the version loaded before opening the modal"
    end)

    _html = render_submit(lv, "create_kura_server", %{"server" => %{"region" => "local-controller"}})

    assert [%{region: "local-controller", current_image_tag: nil}] = Kura.list_servers_for_account(account.id)
  end

  test "deploys the only available Kura region when the portaled form omits inputs", %{
    conn: conn,
    user: user,
    account: account
  } do
    enable_ops_for(user)
    FunWithFlags.enable(:kura, for_actor: account)
    stub(Environment, :dev?, fn -> false end)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings")

    _html = render_submit(lv, "create_kura_server", %{})

    assert [%{region: "local-controller", current_image_tag: nil}] = Kura.list_servers_for_account(account.id)
  end

  defp enable_ops_for(user) do
    stub(Environment, :ops_user_handles, fn -> [user.account.name] end)
  end
end
