defmodule TuistWeb.WebhookLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Webhooks
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp valid_attrs(extras \\ %{}) do
    Map.merge(
      %{
        "name" => "Hook",
        "url" => "https://example.com/hook",
        "event_types" => ["test_case.updated"]
      },
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

  test "renders the endpoint details when no deliveries exist yet", %{conn: conn, account: account} do
    {:ok, endpoint, _} = Webhooks.create_endpoint(account.id, valid_attrs(%{"name" => "Jira"}))

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/webhooks/#{endpoint.id}")

    assert html =~ "Jira"
    assert html =~ "https://example.com/hook"
    assert html =~ "test_case.updated"
    assert html =~ "No deliveries yet"
  end

  test "rotate_endpoint_signing_secret reveals the new secret on the page", %{conn: conn, account: account} do
    {:ok, endpoint, original} = Webhooks.create_endpoint(account.id, valid_attrs())

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/webhooks/#{endpoint.id}")
    html = render_hook(lv, "rotate_endpoint_signing_secret", %{})

    assert html =~ "rotated-webhook-signing-secret"
    # Verify via the worker read path — the dashboard projection
    # omits the encrypted secret on purpose.
    {:ok, reloaded} = Webhooks.get_endpoint(endpoint.id)
    refute reloaded.signing_secret == original
  end

  test "delete_endpoint removes the endpoint and redirects back to the index", %{conn: conn, account: account} do
    {:ok, endpoint, _} = Webhooks.create_endpoint(account.id, valid_attrs())

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/webhooks/#{endpoint.id}")

    assert {:error, {:live_redirect, %{to: redirect_to}}} =
             render_hook(lv, "delete_endpoint", %{})

    assert redirect_to == ~p"/#{account.name}/settings/webhooks"
    assert Webhooks.list_endpoints(account.id) == []
  end

  test "raises NotFoundError for an endpoint in another account", %{conn: conn, account: account} do
    other_account = AccountsFixtures.user_fixture().account
    {:ok, other_endpoint, _} = Webhooks.create_endpoint(other_account.id, valid_attrs())

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/settings/webhooks/#{other_endpoint.id}")
    end
  end
end
