defmodule TuistWeb.ClaudeIntegrationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Anthropic.ControlPlane
  alias Tuist.Sandboxes.Anthropic.Federation

  @snippet """
  curl https://api.anthropic.com/v1/oauth/token -d '{
    "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
    "federation_rule_id": "fdrl_01Rule",
    "organization_id": "00000000-0000-4000-8000-000000000001",
    "service_account_id": "svac_01Account",
    "workspace_id": "wrkspc_01Space"
  }'
  """

  setup %{conn: conn} do
    user = user_fixture()
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    %{conn: log_in_user(conn, user), account: user.account}
  end

  defp exchange_subject(opts) do
    %JOSE.JWT{fields: claims} = JOSE.JWT.peek_payload(opts[:json].assertion)
    claims["sub"]
  end

  test "connects an environment through federation without an API key", %{conn: conn, account: account} do
    test_pid = self()
    {:ok, view, _html} = live(conn, "/#{account.name}/settings/integrations")
    component = with_target(view, "#claude-integration")

    view |> element("#claude-integration button", "Connect") |> render_click()
    assert_push_event(view, "open-modal", %{id: "connect-claude-modal"})
    # The modal body is portaled through a <template>, which element
    # queries do not enter, so its content is checked in the rendered HTML.
    html = render(view)
    assert html =~ ~s(id="claude-issuer-value">#{Federation.issuer(account.id)}</code>)
    assert html =~ ~s(id="claude-subject-value">account:#{account.id}:*</code>)

    render_click(component, "go", %{"step" => "2"})
    render_change(component, "ids-change", %{"snippet" => @snippet})
    html = render(view)
    assert html =~ ~r/id="claude-organization-id"[^>]*value="00000000-0000-4000-8000-000000000001"/
    assert html =~ ~r/id="claude-federation-rule-id"[^>]*value="fdrl_01Rule"/

    ids = %{
      "anthropic_organization_id" => "00000000-0000-4000-8000-000000000001",
      "anthropic_workspace_id" => "wrkspc_01Space",
      "anthropic_service_account_id" => "svac_01Account",
      "anthropic_federation_rule_id" => "fdrl_01Rule"
    }

    expect(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 401, body: %{"error" => %{"message" => "Authentication failed"}}}}
    end)

    render_submit(component, "verify", ids)
    assert render(view) =~ "Anthropic rejected the token"
    assert render(view) =~ ~s(href="#{Federation.authentication_history_url()}")

    # The test exchange and the environment creation each sign a token with
    # the setup subject, since the environment row does not exist yet.
    stub(Req, :post, fn _url, opts ->
      send(test_pid, {:subject, exchange_subject(opts), opts[:json].federation_rule_id})
      {:ok, %Req.Response{status: 200, body: %{"access_token" => "sk-ant-oat01-setup", "expires_in" => 600}}}
    end)

    render_submit(component, "verify", ids)
    assert_received {:subject, subject, "fdrl_01Rule"}
    assert subject == "account:#{account.id}:setup"
    assert render(view) =~ "Anthropic accepted"

    expect(ControlPlane, :create_environment, fn {:bearer, "sk-ant-oat01-setup"}, "agents" ->
      {:ok, %{"id" => "env_01Federated"}}
    end)

    render_submit(component, "create-environment", %{"name" => "agents"})
    assert render(view) =~ ~s(id="claude-environment-id-value">env_01Federated</code>)

    render_submit(component, "connect", %{"environment_key" => "sk-ant-env-secret", "shape" => "darwin-8-16384"})
    assert_push_event(view, "close-modal", %{id: "connect-claude-modal"})
    refute render(view) =~ "sk-ant-env-secret"
    assert has_element?(view, "#claude-integration li", "env_01Federated")
    assert has_element?(view, "#claude-integration li", "Federated")

    assert [environment] = Sandboxes.list_agent_environments(account)
    assert environment.anthropic_environment_id == "env_01Federated"
    assert environment.environment_key == "sk-ant-env-secret"
    assert is_nil(environment.anthropic_api_key)
    assert Federation.federated?(environment)
    assert {environment.platform, environment.vcpus, environment.memory_mb} == {:darwin, 8, 16_384}
    assert environment.name == "agents"
  end

  test "checks the ids before calling Anthropic", %{conn: conn, account: account} do
    {:ok, view, _html} = live(conn, "/#{account.name}/settings/integrations")
    component = with_target(view, "#claude-integration")
    reject(&Req.post/2)

    render_click(component, "go", %{"step" => "2"})

    render_submit(component, "verify", %{
      "anthropic_organization_id" => "not-a-uuid",
      "anthropic_workspace_id" => "wrkspc_01Space",
      "anthropic_service_account_id" => "",
      "anthropic_federation_rule_id" => "fdrl_01Rule"
    })

    assert render(view) =~ "must be the organization&#39;s UUID"
    assert render(view) =~ "can&#39;t be blank"
  end

  test "hidden when sandbox access is disabled", %{conn: conn, account: account} do
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    {:ok, view, _html} = live(conn, "/#{account.name}/settings/integrations")
    assert has_element?(view, "#claude-integration[hidden]")
    refute has_element?(view, "#connect-claude-modal")
  end
end
