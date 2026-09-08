defmodule TuistWeb.CacheLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.SelfHostedClients
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
    stub_non_hosted_deployment()
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Cache · #{account.name} · Tuist"
  end

  test "lists registered self-hosted nodes", %{conn: conn, account: account} do
    stub_non_hosted_deployment()
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

  test "renders on a hosted deployment without a feature flag", %{conn: conn, account: account} do
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/cache")

    assert has_element?(lv, "[data-part=cache-write-policy-card]")
  end

  test "hides the managed cache-servers section on a self-hosted server with no regions", %{
    conn: conn,
    account: account
  } do
    # Simulate a self-hosted production server: no managed regions are
    # available, so only the self-hosted section should render.
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> [] end)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    refute html =~ "Managed cache"
    assert html =~ "Self-hosted servers"
  end

  test "tells the account nothing about where its cache runs", %{conn: conn, account: account} do
    # Placement is not a request the account can make, and not a status it is
    # given either: the page carries no managed-cache surface at all.
    stub_non_hosted_deployment()
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/cache")

    refute has_element?(lv, "[data-part=servers-card]")
    refute html =~ "Managed cache"
    # Where servers run is not a question the account is asked or answered, so
    # the surface names no region and offers no control over one.
    refute html =~ "Local Controller (kind)"
    refute html =~ "Deploy server"
    refute html =~ "create_cache_server"
    refute html =~ "destroy_cache_server"
    refute html =~ "Your cache starts the first time a build uses it."
  end

  test "updates the cache upload access", %{conn: conn, account: account} do
    stub_non_hosted_deployment()
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Upload access"
    assert html =~ "Learn how to authenticate CI"
    assert html =~ ~s(href="/en/docs/guides/server/authentication#continuous-integration")
    assert html =~ "Members, CI and account tokens"
    assert html =~ "CI and account tokens only"
    assert html =~ ~s(id="cache-upload-policy-members-and-tokens")
    assert html =~ ~s(id="cache-upload-policy-tokens-only")
    assert html =~ ~s(phx-value-policy="members_and_tokens")
    document = Floki.parse_fragment!(html)
    assert Floki.attribute(document, "#cache-upload-policy-members-and-tokens", "data-selected") == ["true"]
    assert Floki.attribute(document, "#cache-upload-policy-tokens-only", "data-selected") == ["false"]

    html = render_click(lv, "select_cache_upload_policy", %{"policy" => "tokens_only"})

    assert html =~ ~s(id="cache-upload-policy-tokens-only")
    assert html =~ ~s(phx-value-policy="tokens_only")
    document = Floki.parse_fragment!(html)
    assert Floki.attribute(document, "#cache-upload-policy-members-and-tokens", "data-selected") == ["false"]
    assert Floki.attribute(document, "#cache-upload-policy-tokens-only", "data-selected") == ["true"]

    assert {:ok, updated_account} = Accounts.get_account_by_id(account.id)
    assert updated_account.cache_write_policy == :tokens_only

    html = render_click(lv, "select_cache_upload_policy", %{"policy" => "members_and_tokens"})

    assert html =~ ~s(id="cache-upload-policy-members-and-tokens")
    document = Floki.parse_fragment!(html)
    assert Floki.attribute(document, "#cache-upload-policy-members-and-tokens", "data-selected") == ["true"]
    assert Floki.attribute(document, "#cache-upload-policy-tokens-only", "data-selected") == ["false"]
    assert {:ok, updated_account} = Accounts.get_account_by_id(account.id)
    assert updated_account.cache_write_policy == :members_and_tokens
  end

  test "renders the self-hosted sections", %{conn: conn, account: account} do
    stub_non_hosted_deployment()
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Credentials"
    assert html =~ "Registered nodes"
    assert html =~ "create_self_hosted_client"
  end

  test "hides the self-hosted section without the enterprise entitlement", %{conn: conn, account: account} do
    stub_non_hosted_deployment()
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Billing, :effective_plan, fn _ -> :pro end)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert has_element?(lv, "[data-part=cache-write-policy-card]")
    refute html =~ "Self-hosted servers"
    refute html =~ "create_self_hosted_client"
  end

  test "shows the self-hosted section with the enterprise entitlement", %{conn: conn, account: account} do
    stub_non_hosted_deployment()
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Self-hosted servers"
  end

  test "generates a tenant-scoped credential and reveals the secret once", %{conn: conn, account: account} do
    stub_non_hosted_deployment()
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

    # The list hints at the secret with a suffix-only masked preview.
    assert html =~ "••••••••••••#{client.secret_last_four}"
  end

  test "revokes a credential through the confirmation modal", %{conn: conn, account: account} do
    stub_non_hosted_deployment()
    stub(Kura, :latest_versions, fn 1 -> [] end)
    {:ok, {client, _secret}} = SelfHostedClients.create_self_hosted_client(account, %{name: "production"})

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/cache")

    # The revoke action is a Noora confirmation modal, not a browser confirm.
    assert html =~ "revoke-credential-modal-#{client.id}"
    assert html =~ "Self-hosted nodes using it will stop authenticating"
    refute html =~ ~s(data-confirm)

    html = render_click(lv, "revoke_self_hosted_client", %{"id" => client.id})

    refute html =~ "production"
    assert SelfHostedClients.list_self_hosted_clients(account) == []
  end

  defp stub_non_hosted_deployment do
    stub(Environment, :dev?, fn -> false end)
    # Non-hosted deployments grant every entitlement, so this keeps the
    # self-hosted (Enterprise-only) section available; the entitlement tests
    # override it.
    stub(Environment, :tuist_hosted?, fn -> false end)
  end
end
