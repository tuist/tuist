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
    assert has_element?(view, "#amp-integration button", "Connect Amp")
    view |> element("#amp-integration button", "Connect Amp") |> render_click()
    assert_push_event(view, "open-modal", %{id: "connect-amp-modal"})
    token = "aop_live_fixture_secret"
    view |> with_target("#amp-integration") |> render_submit("save", %{"provider_token" => token})
    assert_push_event(view, "close-modal", %{id: "connect-amp-modal"})
    assert has_element?(view, "#amp-integration", "Starting provider")
    refute render(view) =~ token
    assert AmpIntegrations.get(account.id).provider_token == token
    view |> element("#amp-integration button", "Replace token") |> render_click()
    refute render(view) =~ token

    view
    |> with_target("#amp-integration")
    |> render_submit("save", %{"provider_token" => "aop_live_replaced"})

    view |> element("#amp-integration button", "Disconnect") |> render_click()
    assert has_element?(view, "#amp-integration", "Saved disks remain")
    view |> element("#amp-integration button", "Disconnect Amp") |> render_click()
    assert has_element?(view, "#amp-integration", "Disconnecting")
    assert is_nil(AmpIntegrations.get(account.id).provider_token)
  end

  test "hidden when sandbox access is disabled", %{conn: conn, account: account} do
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    {:ok, view, _} = live(conn, "/#{account.name}/settings/integrations")
    assert has_element?(view, "#amp-integration[hidden]")
  end
end
