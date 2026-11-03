defmodule TuistWeb.AmpIntegrationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Accounts.UserToken
  alias Tuist.Repo
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

  for invalidation <- [:idle, :absolute, :revoked, :sso_policy] do
    @tag :component_authentication
    test "rejects component mutations after #{invalidation} invalidation before the periodic check", %{
      conn: conn,
      user: user
    } do
      organization = organization_fixture(creator: user, sso_provider: :google, sso_organization_id: "example.com")
      {:ok, _} = Accounts.update_organization(organization, %{sso_enforced: true})
      account = organization.account

      session_token =
        Accounts.generate_user_session_token(user, %{auth_method: :google, provider_organization_id: "example.com"})

      conn = put_session(conn, :user_token, session_token)
      {:ok, _} = AmpIntegrations.connect(account.id, user, "aop_live_guard_control")
      {:ok, view, _} = live(conn, "/#{account.name}/settings/integrations")

      view
      |> with_target("#amp-integration")
      |> render_submit("save", %{"provider_token" => "aop_live_allowed_target"})

      assert AmpIntegrations.get(account.id).provider_token == "aop_live_allowed_target"

      case unquote(invalidation) do
        :idle ->
          session = Repo.get_by!(UserToken, token: session_token, context: "session")

          session
          |> Ecto.Changeset.change(last_active_at: DateTime.add(DateTime.utc_now(:second), -901))
          |> Repo.update!()

        :absolute ->
          session = Repo.get_by!(UserToken, token: session_token, context: "session")

          session
          |> Ecto.Changeset.change(inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(:second), -28_801))
          |> Repo.update!()

        :revoked ->
          Accounts.delete_user_session_token(session_token)

        :sso_policy ->
          {:ok, _} = Accounts.update_organization(organization, %{sso_organization_id: "new.example.com"})
      end

      view |> with_target("#amp-integration") |> render_hook("disconnect", %{})
      integration = AmpIntegrations.get(account.id)
      assert integration.enabled
      assert integration.provider_token == "aop_live_allowed_target"
      assert_redirect(view, if(unquote(invalidation) == :sso_policy, do: "/users/auth/google", else: "/users/log_in"))
    end
  end

  test "an authorized account-bound support grant retains component access without customer SSO proof", %{
    conn: conn,
    user: owner
  } do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    organization = organization_fixture(creator: owner, sso_provider: :google, sso_organization_id: "customer.example")
    {:ok, _} = Accounts.update_organization(organization, %{sso_enforced: true})
    operator = user_fixture(email: "component-support@tuist.dev")
    oauth2_identity_fixture(user: operator, provider: :google, provider_organization_id: "tuist.dev")
    account = organization.account
    {:ok, _} = AmpIntegrations.connect(account.id, owner, "aop_live_support")

    grant = %{
      tier: :admin,
      account_id: account.id,
      account_handle: account.name,
      sub: operator.email,
      jti: "component-support-proof",
      exp: System.system_time(:second) + 600
    }

    conn = conn |> log_in_user(operator) |> put_session(:operator_grants, %{account.name => grant})
    {:ok, view, _} = live(conn, "/#{account.name}/settings/integrations")
    view |> with_target("#amp-integration") |> render_hook("disconnect", %{})
    refute AmpIntegrations.get(account.id).enabled
    assert is_nil(AmpIntegrations.get(account.id).provider_token)
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
