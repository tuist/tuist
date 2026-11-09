defmodule TuistWeb.ClaudeIntegrationLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Anthropic.ControlPlane
  alias Tuist.Sandboxes.Anthropic.Federation

  setup %{conn: conn} do
    user = user_fixture()
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    %{conn: log_in_user(conn, user), account: user.account}
  end

  defp exchange_subject(opts) do
    %JOSE.JWT{fields: claims} = JOSE.JWT.peek_payload(opts[:json].assertion)
    claims["sub"]
  end

  test "connects an environment with a federated identity", %{conn: conn, account: account} do
    test_pid = self()
    {:ok, view, _html} = live(conn, "/#{account.name}/settings/integrations")
    component = with_target(view, "#claude-integration")

    view |> element("#claude-integration button", "Connect") |> render_click()
    assert_push_event(view, "open-modal", %{id: "connect-claude-modal"})
    render_click(component, "auth", %{"mode" => "federation"})
    # The modal body is portaled through a <template>, which element
    # queries do not enter, so its content is checked in the rendered HTML.
    html = render(view)
    assert html =~ ~s(id="claude-issuer-value">#{Federation.issuer(account.id)}</code>)
    assert html =~ ~s(id="claude-subject-value">account:#{account.id}:*</code>)

    params = %{
      "anthropic_organization_id" => "00000000-0000-4000-8000-000000000001",
      "anthropic_workspace_id" => "wrkspc_01Space",
      "anthropic_service_account_id" => "svac_01Account",
      "anthropic_federation_rule_id" => "fdrl_01Rule",
      "environment_id" => "env_01Federated",
      "environment_key" => "sk-ant-env-secret",
      "shape" => "darwin-8-16384"
    }

    expect(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 401, body: %{"error" => %{"message" => "Authentication failed"}}}}
    end)

    render_submit(component, "connect", params)
    assert render(view) =~ "Anthropic rejected the token"
    assert render(view) =~ ~s(href="#{Federation.authentication_history_url()}")
    assert Sandboxes.list_agent_environments(account) == []

    # The check signs a token with the setup subject, since the agent
    # environment row does not exist yet.
    stub(Req, :post, fn _url, opts ->
      send(test_pid, {:subject, exchange_subject(opts), opts[:json].federation_rule_id})
      {:ok, %Req.Response{status: 200, body: %{"access_token" => "sk-ant-oat01-setup", "expires_in" => 600}}}
    end)

    expect(ControlPlane, :get_environment, fn {:bearer, "sk-ant-oat01-setup"}, "env_01Federated" ->
      {:ok, %{"id" => "env_01Federated", "name" => "agents", "config" => %{"type" => "self_hosted"}}}
    end)

    render_submit(component, "connect", params)
    assert_received {:subject, subject, "fdrl_01Rule"}
    assert subject == "account:#{account.id}:setup"
    assert_push_event(view, "close-modal", %{id: "connect-claude-modal"})
    refute render(view) =~ "sk-ant-env-secret"
    assert has_element?(view, "#claude-integration li", "env_01Federated")
    refute has_element?(view, "#claude-integration li .noora-badge")

    assert [environment] = Sandboxes.list_agent_environments(account)
    assert environment.anthropic_environment_id == "env_01Federated"
    assert environment.environment_key == "sk-ant-env-secret"
    assert is_nil(environment.anthropic_api_key)
    assert Federation.federated?(environment)
    assert {environment.platform, environment.vcpus, environment.memory_mb} == {:darwin, 8, 16_384}
    assert environment.name == "agents"
  end

  test "connects an environment with an API key", %{conn: conn, account: account} do
    {:ok, view, _html} = live(conn, "/#{account.name}/settings/integrations")
    component = with_target(view, "#claude-integration")
    # No federation exchange on this path.
    reject(&Req.post/2)

    # The form opens on the API-key path.
    view |> element("#claude-integration button", "Connect") |> render_click()
    assert render(view) =~ ~s(name="api_key")
    refute render(view) =~ ~s(name="anthropic_organization_id")

    params = %{"environment_id" => "env_01ApiKey", "environment_key" => "sk-ant-env-secret", "shape" => "linux-2-4096"}

    expect(ControlPlane, :get_environment, fn {:api_key, "sk-ant-api03-wrong"}, "env_01ApiKey" ->
      {:error, %{status: 401, message: "invalid x-api-key"}}
    end)

    render_submit(component, "connect", Map.put(params, "api_key", " sk-ant-api03-wrong "))
    assert render(view) =~ "Anthropic rejected the API key"
    refute render(view) =~ "sk-ant-api03-wrong"

    expect(ControlPlane, :get_environment, fn {:api_key, "sk-ant-api03-secret"}, "env_01ApiKey" ->
      {:ok, %{"id" => "env_01ApiKey", "name" => "trial", "config" => %{"type" => "self_hosted"}}}
    end)

    render_submit(component, "connect", Map.put(params, "api_key", "sk-ant-api03-secret"))
    assert_push_event(view, "close-modal", %{id: "connect-claude-modal"})
    html = render(view)
    refute html =~ "sk-ant-api03-secret"
    refute html =~ "sk-ant-env-secret"
    assert has_element?(view, "#claude-integration li .noora-badge", "API key")

    assert [environment] = Sandboxes.list_agent_environments(account)
    assert environment.anthropic_environment_id == "env_01ApiKey"
    assert environment.anthropic_api_key == "sk-ant-api03-secret"
    assert environment.environment_key == "sk-ant-env-secret"
    refute Federation.federated?(environment)
    assert environment.name == "trial"
  end

  test "refuses an environment Anthropic hosts itself", %{conn: conn, account: account} do
    {:ok, view, _html} = live(conn, "/#{account.name}/settings/integrations")
    component = with_target(view, "#claude-integration")

    expect(ControlPlane, :get_environment, fn {:api_key, "sk-ant-api03-secret"}, "env_01Cloud" ->
      {:ok, %{"id" => "env_01Cloud", "name" => "cloud", "config" => %{"type" => "cloud"}}}
    end)

    render_submit(component, "connect", %{
      "api_key" => "sk-ant-api03-secret",
      "environment_id" => "env_01Cloud",
      "environment_key" => "sk-ant-env-secret",
      "shape" => "linux-2-4096"
    })

    assert render(view) =~ "This environment is not self-hosted"
    assert Sandboxes.list_agent_environments(account) == []
  end

  test "checks the fields before calling Anthropic", %{conn: conn, account: account} do
    {:ok, view, _html} = live(conn, "/#{account.name}/settings/integrations")
    component = with_target(view, "#claude-integration")
    reject(&Req.post/2)
    reject(&ControlPlane.get_environment/2)

    render_click(component, "auth", %{"mode" => "federation"})

    render_submit(component, "connect", %{
      "anthropic_organization_id" => "not-a-uuid",
      "anthropic_workspace_id" => "wrkspc_01Space",
      "anthropic_service_account_id" => "",
      "anthropic_federation_rule_id" => "fdrl_01Rule",
      "environment_id" => "env_01Federated",
      "environment_key" => " ",
      "shape" => "linux-2-4096"
    })

    html = render(view)
    assert html =~ "must be the organization&#39;s UUID"
    assert html =~ ~r/can&#39;t be blank.*can&#39;t be blank/s
  end

  test "hidden when sandbox access is disabled", %{conn: conn, account: account} do
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    {:ok, view, _html} = live(conn, "/#{account.name}/settings/integrations")
    assert has_element?(view, "#claude-integration[hidden]")
    refute has_element?(view, "#connect-claude-modal")
  end
end
