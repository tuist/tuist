defmodule TuistWeb.AmpIntegrationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Sandboxes.AmpIntegrations

  setup %{conn: conn} do
    user = user_fixture()
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    %{conn: log_in_user(conn, user), user: user, account: user.account}
  end

  test "connects, replaces and disconnects without rendering saved credentials", %{conn: conn, account: account} do
    {:ok, view, _} = live(conn, "/#{account.name}/settings/integrations")
    assert has_element?(view, "#amp-integration button", "Connect")
    view |> element("#amp-integration button", "Connect") |> render_click()
    assert_push_event(view, "open-modal", %{id: "connect-amp-modal"})
    token = "aop_live_fixture_secret"
    view |> with_target("#amp-integration") |> render_submit("save", %{"provider_token" => token})
    assert_push_event(view, "close-modal", %{id: "connect-amp-modal"})
    refute has_element?(view, "#amp-integration", "Starting provider")
    refute has_element?(view, "#amp-integration button", "Refresh status")
    refute has_element?(view, "#amp-integration", "Your token is saved.")
    assert has_element?(view, "#amp-settings-form-1 button[disabled]", "Save changes")
    assert has_element?(view, "#amp-settings-form-1 input[name=provider_token][value='']")
    refute render(view) =~ token
    assert AmpIntegrations.get(account.id).provider_token == token
    view |> form("#amp-settings-form-1", provider_token: "") |> render_submit()
    assert AmpIntegrations.get(account.id).provider_token == token

    view
    |> form("#amp-settings-form-1", provider_token: "aop_live_replaced")
    |> render_change()

    refute has_element?(view, "#amp-settings-form-1 button[disabled]", "Save changes")
    refute render(view) =~ "aop_live_replaced"

    view |> form("#amp-settings-form-1", provider_token: "aop_live_replaced") |> render_submit()
    assert AmpIntegrations.get(account.id).provider_token == "aop_live_replaced"
    assert has_element?(view, "#amp-settings-form-2 button[disabled]", "Save changes")
    refute render(view) =~ "aop_live_replaced"

    view |> element("#amp-integration button", "Disconnect") |> render_click()
    assert_push_event(view, "open-modal", %{id: "disconnect-amp-modal"})
    assert has_element?(view, "#amp-settings-form-2 input[name=provider_token]")
    refute has_element?(view, "#amp-settings-form-2", "Saved disks remain")
    view |> with_target("#amp-integration") |> render_click("cancel-disconnect")
    assert_push_event(view, "close-modal", %{id: "disconnect-amp-modal"})
    assert AmpIntegrations.get(account.id).enabled
    view |> element("#amp-integration button", "Disconnect") |> render_click()
    assert_push_event(view, "open-modal", %{id: "disconnect-amp-modal"})
    view |> with_target("#amp-integration") |> render_click("disconnect")
    assert_push_event(view, "close-modal", %{id: "disconnect-amp-modal"})
    assert has_element?(view, "#amp-integration button", "Connect")
    refute has_element?(view, "#amp-integration input[name=provider_token]")
    assert is_nil(AmpIntegrations.get(account.id).provider_token)
  end

  test "hidden when sandbox access is disabled", %{conn: conn, account: account} do
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    {:ok, view, _} = live(conn, "/#{account.name}/settings/integrations")
    assert has_element?(view, "#amp-integration[hidden]")
    refute has_element?(view, "#connect-amp-modal")
    refute has_element?(view, "#disconnect-amp-modal")
  end

  test "existing connection is hidden when sandbox access is disabled", %{conn: conn, account: account, user: user} do
    assert {:ok, _} = AmpIntegrations.connect(account.id, user, "aop_live_existing")
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    {:ok, view, _} = live(conn, "/#{account.name}/settings/integrations")
    assert has_element?(view, "#amp-integration[hidden]")
    refute has_element?(view, "#connect-amp-modal")
    refute has_element?(view, "#disconnect-amp-modal")
  end
end
