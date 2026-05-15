defmodule TuistWeb.WebhooksLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Webhooks
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp valid_attrs(extras \\ %{}) do
    Map.merge(
      %{"name" => "Hook", "url" => "https://example.com/hook", "event_types" => ["test_case.updated"]},
      extras
    )
  end

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
    render_hook(lv, "toggle_create_form_event_type", %{"data" => "test_case.updated"})
    html = render_hook(lv, "create_endpoint", %{})

    # Disclosure state: plaintext secret is rendered, prefixed with tuist_webhook_
    assert html =~ "new-webhook-signing-secret"
    assert html =~ "tuist_webhook_"

    # The endpoint is persisted with the selected event subscriptions.
    assert [endpoint] = Webhooks.list_endpoints(account.id)
    assert endpoint.name == "Jira"
    assert endpoint.url == "https://example.com/hook"
    assert endpoint.event_types == ["test_case.updated"]
    assert is_binary(endpoint.signing_secret)
    assert String.starts_with?(endpoint.signing_secret, "tuist_webhook_")

    # After dismissing, the secret is no longer in the rendered HTML.
    html = render_hook(lv, "dismiss_disclosure", %{})
    refute html =~ "new-webhook-signing-secret"
  end

  test "rejects a non-HTTPS URL inline", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")

    render_hook(lv, "update_create_form_name", %{"value" => "Bad"})
    render_hook(lv, "update_create_form_url", %{"value" => "http://example.com/hook"})
    render_hook(lv, "toggle_create_form_event_type", %{"data" => "test_case.updated"})
    html = render_hook(lv, "create_endpoint", %{})

    assert html =~ "must be a valid HTTPS URL"
    assert Webhooks.list_endpoints(account.id) == []
  end

  test "rejects creation when no event types are selected", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")

    render_hook(lv, "update_create_form_name", %{"value" => "Empty"})
    render_hook(lv, "update_create_form_url", %{"value" => "https://example.com/hook"})
    html = render_hook(lv, "create_endpoint", %{})

    assert html =~ "must subscribe to at least one event"
    assert Webhooks.list_endpoints(account.id) == []
  end

  test "toggle_create_form_event_type unchecks a previously selected event", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")

    render_hook(lv, "update_create_form_name", %{"value" => "Toggle"})
    render_hook(lv, "update_create_form_url", %{"value" => "https://example.com/hook"})
    render_hook(lv, "toggle_create_form_event_type", %{"data" => "test_case.updated"})
    # Toggle off; the empty-subscription validation should now reject the create.
    render_hook(lv, "toggle_create_form_event_type", %{"data" => "test_case.updated"})
    html = render_hook(lv, "create_endpoint", %{})

    assert html =~ "must subscribe to at least one event"
    assert Webhooks.list_endpoints(account.id) == []
  end

  test "toggle_create_form_event_group selects every event in the group at once", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")

    render_hook(lv, "update_create_form_name", %{"value" => "Bulk"})
    render_hook(lv, "update_create_form_url", %{"value" => "https://example.com/hook"})
    render_hook(lv, "toggle_create_form_event_group", %{"data" => "test_cases"})
    render_hook(lv, "create_endpoint", %{})

    assert [endpoint] = Webhooks.list_endpoints(account.id)
    assert Enum.sort(endpoint.event_types) == Enum.sort(~w(test_case.created test_case.updated))
  end

  test "toggle_create_form_event_group deselects the group when every event is already selected", %{
    conn: conn,
    account: account
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")

    render_hook(lv, "update_create_form_name", %{"value" => "Toggle off"})
    render_hook(lv, "update_create_form_url", %{"value" => "https://example.com/hook"})
    # Select all by group, then toggle the group again — should clear all.
    render_hook(lv, "toggle_create_form_event_group", %{"data" => "test_cases"})
    render_hook(lv, "toggle_create_form_event_group", %{"data" => "test_cases"})
    html = render_hook(lv, "create_endpoint", %{})

    assert html =~ "must subscribe to at least one event"
    assert Webhooks.list_endpoints(account.id) == []
  end

  test "rotate_endpoint_signing_secret replaces the secret and shows the new one", %{
    conn: conn,
    account: account
  } do
    {:ok, endpoint, original} = Webhooks.create_endpoint(account.id, valid_attrs())

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")
    html = render_hook(lv, "rotate_endpoint_signing_secret", %{"id" => endpoint.id})

    assert html =~ "new-webhook-signing-secret"
    {:ok, reloaded} = Webhooks.get_account_endpoint(endpoint.id, account.id)
    refute reloaded.signing_secret == original
  end

  test "delete_endpoint removes the endpoint", %{conn: conn, account: account} do
    {:ok, endpoint, _} = Webhooks.create_endpoint(account.id, valid_attrs())

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")
    render_hook(lv, "delete_endpoint", %{"id" => endpoint.id})

    assert Webhooks.list_endpoints(account.id) == []
  end

  test "delete_endpoint does not delete an endpoint in another account", %{conn: conn, account: account} do
    other_account = AccountsFixtures.user_fixture().account

    {:ok, other_endpoint, _} =
      Webhooks.create_endpoint(other_account.id, valid_attrs(%{"name" => "Other", "url" => "https://other.example/hook"}))

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/webhooks")
    render_hook(lv, "delete_endpoint", %{"id" => other_endpoint.id})

    assert [_] = Webhooks.list_endpoints(other_account.id)
  end
end
