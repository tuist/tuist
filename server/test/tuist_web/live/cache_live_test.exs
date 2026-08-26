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

  test "is available on a self-hosted server without the kura flag", %{conn: conn, account: account} do
    # Non-hosted deployments grant the Kura surface unconditionally, so the
    # page and credential generation work even with the flag off.
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> false end)
    stub_cache_flag(account, false)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    refute html =~ "not enabled for this account"
    assert html =~ "Self-hosted servers"
    assert html =~ "create_self_hosted_client"
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
    stub_cache_flag(account, false)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    refute html =~ "Managed cache"
    assert html =~ "Self-hosted servers"
  end

  test "renders on the hosted server when the kura flag is on", %{conn: conn, account: account} do
    # Positive coverage for the hosted branch: with tuist_hosted? true the
    # `not tuist_hosted?()` disjunct is false, so the surface appears only
    # because the :kura flag is on for the account.
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub_cache_flag(account, true)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/cache")

    refute html =~ "not enabled for this account"
    assert has_element?(lv, "[data-part=servers-card]")
  end

  test "renders cache servers for cache-enabled accounts", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.2", released_at: DateTime.utc_now(:second)}] end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert has_element?(lv, "[data-part=servers-card]")
    assert html =~ "Managed cache"
    # Where servers run is not a question the account is asked or answered, so
    # the surface names no region and offers no control over one.
    refute html =~ "Local Controller (kind)"
    refute html =~ "Deploy server"
    refute html =~ "create_cache_server"
    refute html =~ "destroy_cache_server"
    assert html =~ "Your cache starts the first time a build uses it."
  end

  test "updates the cache upload access", %{conn: conn, account: account} do
    enable_cache(account)
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

  test "reports a serving cache without naming where it runs", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [%{version: "0.5.3", released_at: DateTime.utc_now(:second)}] end)

    {:ok, server} = Kura.create_server(%{account_id: account.id, region: "local-controller", image_tag: "0.5.2"})

    deployment = hd(server.deployments)
    {:ok, deployment} = Kura.mark_running(deployment)
    {:ok, _deployment} = Kura.mark_succeeded(deployment)
    {:ok, server} = Kura.activate_server(server, "0.5.2")

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Active"
    assert html =~ "Your cache is serving builds."
    # The domain names a region, which is the one thing this surface must not
    # anchor a region request on.
    refute html =~ server.url
  end

  test "renders a replicating server without crashing", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, server} =
      Kura.create_server(%{account_id: account.id, region: "local-controller", image_tag: "0.5.2"})

    {:ok, _server} =
      Kura.record_observation(server, %{status: :replicating, current_image_tag: "0.5.2"})

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Setting up"
    assert html =~ "Builds keep working while it warms up."
  end

  test "renders the self-hosted sections", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Credentials"
    assert html =~ "Registered nodes"
    assert html =~ "create_self_hosted_client"
  end

  test "hides the self-hosted section without the enterprise entitlement", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Billing, :effective_plan, fn _ -> :pro end)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert has_element?(lv, "[data-part=servers-card]")
    refute html =~ "Self-hosted servers"
    refute html =~ "create_self_hosted_client"
  end

  test "shows the self-hosted section with the enterprise entitlement", %{conn: conn, account: account} do
    enable_cache(account)
    stub(Environment, :tuist_hosted?, fn -> true end)
    stub(Tuist.Billing, :effective_plan, fn _ -> :enterprise end)
    stub(Kura, :latest_versions, fn 1 -> [] end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/cache")

    assert html =~ "Self-hosted servers"
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

    # The list hints at the secret with a suffix-only masked preview.
    assert html =~ "••••••••••••#{client.secret_last_four}"
  end

  test "revokes a credential through the confirmation modal", %{conn: conn, account: account} do
    enable_cache(account)
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

  test "names no region however many the account is served from" do
    # Every region the account holds is one more thing a customer could ask to
    # change. The serving view answers whether the cache works, and nothing
    # else, so there is no region word to anchor that request on.
    html = render_component(&TuistWeb.CacheLive.cache_servers_section/1, %{serving_state: :active})

    assert html =~ "Active"
    refute html =~ "us-east"
    refute html =~ "kura.tuist.dev"
    refute html =~ "Deploy"
    refute html =~ "Destroy"
  end

  test "the deploy and destroy controls are gone" do
    enable_cache_for_component = %{serving_state: :absent}

    html = render_component(&TuistWeb.CacheLive.cache_servers_section/1, enable_cache_for_component)

    refute html =~ "create_cache_server"
    refute html =~ "destroy_cache_server"
    refute html =~ "retry_cache_server"
  end

  defp enable_cache(account) do
    stub(Environment, :dev?, fn -> false end)
    # Non-hosted deployments grant every entitlement, so this keeps the
    # self-hosted (Enterprise-only) section available; gate tests override it.
    stub(Environment, :tuist_hosted?, fn -> false end)
    stub_cache_flag(account, true)
  end

  defp disable_cache(account) do
    stub(Environment, :dev?, fn -> false end)
    # The Cache surface is on by default on non-hosted deployments, so the
    # only way it stays hidden is the hosted server with the flag off.
    stub(Environment, :tuist_hosted?, fn -> true end)
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
