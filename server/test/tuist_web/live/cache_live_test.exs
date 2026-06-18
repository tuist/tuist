defmodule TuistWeb.CacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.SelfHostedClients
  alias Tuist.Kura.Server
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
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Cache · #{account.name} · Tuist"
  end

  test "lists registered self-hosted nodes", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _endpoint} =
      Tuist.Kura.Registrations.register_heartbeat(account, %{
        node_id: "kura-office-0",
        advertised_http_url: "https://cache.acme.internal",
        region: "us-office",
        ready: true,
        version: "0.5.2"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Registered nodes"
    assert html =~ "kura-office-0"
    assert html =~ "https://cache.acme.internal"
  end

  test "raises UnauthorizedError when the user is not authorized", %{conn: conn} do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    user = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(user, organization)
    conn = log_in_user(conn, user)

    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      live(conn, ~p"/#{organization.account.name}/cache")
    end
  end

  test "shows a disabled notice when cache is not enabled", %{conn: conn, account: account} do
    disable_cache(account)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "not enabled for this account"
    refute html =~ "create_self_hosted_client"
    refute html =~ "cache-servers-table"
  end

  test "renders cache servers for cache-enabled accounts", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Cache servers"
    assert html =~ "Local Controller (kind)"
    assert has_element?(lv, "button", "Deploy server")
    assert html =~ "create_cache_server"
    assert html =~ ~s(phx-value-region="local-controller")
    assert has_element?(lv, "#cache-servers-table")
    assert html =~ "Not deployed"
    refute html =~ "Kura"
  end

  test "shows cache server state, domain, and version", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.3", released_at: DateTime.utc_now(:second)}] end)

    {:ok, server} = Kura.create_server(%{account_id: account.id, region: "local-controller", image_tag: "0.5.2"})

    deployment = hd(server.deployments)
    {:ok, deployment} = Kura.mark_running(deployment)
    {:ok, _deployment} = Kura.mark_succeeded(deployment)
    {:ok, server} = Kura.activate_server(server, "0.5.2")

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Active"
    assert html =~ server.url
    assert html =~ "0.5.2"
  end

  test "renders the self-hosted sections", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Node credentials"
    assert html =~ "Cache endpoints"
    assert html =~ "create_self_hosted_client"
    assert html =~ "create_self_hosted_endpoint"
  end

  test "generates a tenant-scoped credential and reveals the secret once", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/cache")

    html = render_submit(lv, "create_self_hosted_client", %{"self_hosted_client" => %{"name" => "production"}})

    assert html =~ "production"
    assert html =~ "Client secret"
    assert [client] = SelfHostedClients.list_self_hosted_clients(account)
    assert client.name == "production"

    html = render_click(lv, "dismiss_self_hosted_client_secret")
    refute html =~ "Client secret"
    assert html =~ "production"
  end

  test "adds and deletes a self-hosted endpoint URL", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/cache")

    html =
      render_submit(lv, "create_self_hosted_endpoint", %{
        "account_cache_endpoint" => %{"url" => "https://mesh.acme.test"}
      })

    assert html =~ "https://mesh.acme.test"
    assert [endpoint] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted)

    html = render_click(lv, "delete_self_hosted_endpoint", %{"id" => endpoint.id})
    refute html =~ "https://mesh.acme.test"
    assert Accounts.list_account_cache_endpoints(account, :kura_self_hosted) == []
  end

  test "shows the cache server endpoint in the table" do
    html = render_component(&TuistWeb.CacheLive.cache_servers_section/1, cache_section_assigns())

    assert html =~ "https://test-org-us-east-1.kura.tuist.dev"
  end

  test "allows adding another managed region when one is already deployed", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> ["eu-central", "us-east", "us-west"] end)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "kura@0.5.2", image_tag: "0.5.2", released_at: nil}] end)

    {:ok, _server} = Kura.create_server(%{account_id: account.id, region: "eu-central", image_tag: "0.5.2"})

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "US East"
    assert html =~ "US West"
    assert html =~ "Not deployed"
    assert html =~ ~s(phx-value-region="us-east")
    assert has_element?(lv, "button", "Deploy server")
  end

  test "deploys a cache server", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/cache")

    _html = render_submit(lv, "create_cache_server", %{"server" => %{"region" => "local-controller"}})

    assert [%{region: "local-controller", current_image_tag: nil}] = Kura.list_servers_for_account(account.id)
  end

  defp cache_section_assigns do
    server = %Server{
      id: 1,
      region: "us-east",
      status: :active,
      url: "https://test-org-us-east-1.kura.tuist.dev",
      current_image_tag: "0.5.2",
      observed_image_tag: "0.5.2"
    }

    %{
      servers: [server],
      available_regions: [],
      add_cache_server_form: Phoenix.Component.to_form(%{}, as: :server),
      latest_version: nil
    }
  end

  defp enable_cache(account) do
    stub(Environment, :dev?, fn -> false end)
    stub_cache_flag(account, true)
  end

  defp disable_cache(account) do
    stub(Environment, :dev?, fn -> false end)
    stub_cache_flag(account, false)
  end

  defp stub_cache_flag(account, enabled?) do
    account_id = account.id

    stub(FunWithFlags, :enabled?, fn
      :kura, [for: %{id: ^account_id}] -> enabled?
      flag, opts -> Mimic.call_original(FunWithFlags, :enabled?, [flag, opts])
    end)
  end
end
