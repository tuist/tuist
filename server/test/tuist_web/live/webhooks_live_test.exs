defmodule TuistWeb.WebhooksLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Webhooks
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(name: "test-org", creator: user, preload: [:account])

    conn = conn |> assign(:selected_account, account) |> log_in_user(user)
    %{conn: conn, user: user, account: account}
  end

  test "renders the empty state when no endpoints exist", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/webhooks")
    assert html =~ "No webhook endpoints yet"
  end

  test "creates an endpoint and reveals the signing secret once", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")

    render_hook(lv, "update_create_form_name", %{"value" => "Jira"})
    render_hook(lv, "update_create_form_url", %{"value" => "https://example.com/hook"})
    html = render_hook(lv, "create_endpoint", %{})

    # Disclosure state: plaintext secret is rendered, prefixed with whsec_
    assert html =~ "new-webhook-signing-secret"
    assert html =~ "whsec_"

    # The endpoint is persisted and the signing secret column is non-empty.
    assert [endpoint] = Webhooks.list_endpoints(account.id)
    assert endpoint.name == "Jira"
    assert endpoint.url == "https://example.com/hook"
    assert is_binary(endpoint.signing_secret)
    assert String.starts_with?(endpoint.signing_secret, "whsec_")

    # After dismissing, the secret is no longer in the rendered HTML.
    html = render_hook(lv, "dismiss_disclosure", %{})
    refute html =~ "new-webhook-signing-secret"
  end

  test "rejects a non-HTTPS URL inline", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")

    render_hook(lv, "update_create_form_name", %{"value" => "Bad"})
    render_hook(lv, "update_create_form_url", %{"value" => "http://example.com/hook"})
    html = render_hook(lv, "create_endpoint", %{})

    assert html =~ "must be a valid HTTPS URL"
    assert Webhooks.list_endpoints(account.id) == []
  end

  test "rotate_endpoint_signing_secret replaces the secret and shows the new one", %{
    conn: conn,
    account: account
  } do
    {:ok, endpoint, original} =
      Webhooks.create_endpoint(account.id, %{"name" => "Hook", "url" => "https://example.com/hook"})

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")
    html = render_hook(lv, "rotate_endpoint_signing_secret", %{"id" => endpoint.id})

    assert html =~ "new-webhook-signing-secret"
    {:ok, reloaded} = Webhooks.get_account_endpoint(endpoint.id, account.id)
    refute reloaded.signing_secret == original
  end

  test "delete_endpoint removes the endpoint", %{conn: conn, account: account} do
    {:ok, endpoint, _} =
      Webhooks.create_endpoint(account.id, %{"name" => "Hook", "url" => "https://example.com/hook"})

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")
    render_hook(lv, "delete_endpoint", %{"id" => endpoint.id})

    assert Webhooks.list_endpoints(account.id) == []
  end

  test "delete_endpoint does not delete an endpoint in another account", %{conn: conn, account: account} do
    other_account = AccountsFixtures.user_fixture().account

    {:ok, other_endpoint, _} =
      Webhooks.create_endpoint(other_account.id, %{"name" => "Other", "url" => "https://other.example/hook"})

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")
    render_hook(lv, "delete_endpoint", %{"id" => other_endpoint.id})

    assert [_] = Webhooks.list_endpoints(other_account.id)
  end
end
