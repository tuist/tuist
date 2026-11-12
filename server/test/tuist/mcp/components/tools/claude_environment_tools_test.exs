defmodule Tuist.MCP.Components.Tools.ClaudeEnvironmentToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.ConnectClaudeEnvironment
  alias Tuist.MCP.Components.Tools.ListClaudeEnvironments
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Anthropic.ControlPlane
  alias Tuist.Sandboxes.Anthropic.Federation
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    admin = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: admin, preload: [:account])
    member = AccountsFixtures.user_fixture(preload: [:account])
    Accounts.add_user_to_organization(member, organization, role: :user)

    %{admin: admin, member: member, account: organization.account, handle: organization.account.name}
  end

  defp user_conn(user), do: %Plug.Conn{assigns: %{current_user: user}}

  defp self_hosted(id, name), do: {:ok, %{"id" => id, "name" => name, "config" => %{"type" => "self_hosted"}}}

  test "an admin connects an environment with an API key and lists it", %{admin: admin, account: account, handle: handle} do
    reject(&Req.post/2)

    expect(ControlPlane, :get_environment, fn {:api_key, "sk-ant-api03-secret"}, "env_01ApiKey" ->
      self_hosted("env_01ApiKey", "trial")
    end)

    result =
      ConnectClaudeEnvironment.call(user_conn(admin), %{
        "account_handle" => handle,
        "environment_id" => "env_01ApiKey",
        "environment_key" => "sk-ant-env-secret",
        "api_key" => " sk-ant-api03-secret "
      })

    refute result["isError"]
    refute JSON.encode!(result) =~ "secret"

    assert %{
             "anthropic_environment_id" => "env_01ApiKey",
             "name" => "trial",
             "authentication" => "api_key",
             "platform" => "linux",
             "vcpus" => 2,
             "memory_mb" => 4096
           } = result["structuredContent"]

    assert [environment] = Sandboxes.list_agent_environments(account)
    assert environment.kind == :managed_agents
    assert environment.anthropic_api_key == "sk-ant-api03-secret"
    assert environment.environment_key == "sk-ant-env-secret"

    listed = ListClaudeEnvironments.call(user_conn(admin), %{"account_handle" => handle})
    refute JSON.encode!(listed) =~ "secret"

    assert %{
             "environments" => [%{"anthropic_environment_id" => "env_01ApiKey", "authentication" => "api_key"}],
             "federation_issuer_url" => issuer,
             "federation_subject_prefix" => prefix
           } = listed["structuredContent"]

    assert issuer == Federation.issuer(account.id)
    assert prefix == "account:#{account.id}:*"
  end

  test "connects an environment with a federated identity", %{admin: admin, account: account, handle: handle} do
    stub(Req, :post, fn _url, opts ->
      assert opts[:json].federation_rule_id == "fdrl_01Rule"
      {:ok, %Req.Response{status: 200, body: %{"access_token" => "sk-ant-oat01-setup", "expires_in" => 600}}}
    end)

    expect(ControlPlane, :get_environment, fn {:bearer, "sk-ant-oat01-setup"}, "env_01Federated" ->
      self_hosted("env_01Federated", "agents")
    end)

    result =
      ConnectClaudeEnvironment.call(user_conn(admin), %{
        "account_handle" => handle,
        "environment_id" => "env_01Federated",
        "environment_key" => "sk-ant-env-secret",
        "organization_id" => "00000000-0000-4000-8000-000000000001",
        "workspace_id" => "wrkspc_01Space",
        "service_account_id" => "svac_01Account",
        "federation_rule_id" => "fdrl_01Rule",
        "platform" => "darwin",
        "vcpus" => 8,
        "memory_mb" => 16_384
      })

    assert %{"authentication" => "federation", "platform" => "darwin", "memory_mb" => 16_384} =
             result["structuredContent"]

    assert [environment] = Sandboxes.list_agent_environments(account)
    assert Federation.federated?(environment)
    assert is_nil(environment.anthropic_api_key)
  end

  test "checks the credential before calling Anthropic", %{admin: admin, account: account, handle: handle} do
    reject(&ControlPlane.get_environment/2)
    reject(&Req.post/2)
    base = %{"account_handle" => handle, "environment_id" => "env_01X", "environment_key" => "sk-ant-env-secret"}

    assert error_text(ConnectClaudeEnvironment.call(user_conn(admin), base)) =~ "Provide api_key or"

    both = Map.merge(base, %{"api_key" => "sk-ant-api03-secret", "workspace_id" => "wrkspc_01Space"})
    assert error_text(ConnectClaudeEnvironment.call(user_conn(admin), both)) =~ "not both"

    partial =
      Map.merge(base, %{"organization_id" => "00000000-0000-4000-8000-000000000001", "workspace_id" => "wrkspc_01Space"})

    text = error_text(ConnectClaudeEnvironment.call(user_conn(admin), partial))
    assert text =~ "service_account_id"
    assert text =~ "federation_rule_id"

    assert Sandboxes.list_agent_environments(account) == []
  end

  test "stores nothing when Anthropic refuses the environment", %{admin: admin, account: account, handle: handle} do
    expect(ControlPlane, :get_environment, fn {:api_key, _key}, "env_01Missing" ->
      {:error, %{status: 404, message: "not found"}}
    end)

    result =
      ConnectClaudeEnvironment.call(user_conn(admin), %{
        "account_handle" => handle,
        "environment_id" => "env_01Missing",
        "environment_key" => "sk-ant-env-secret",
        "api_key" => "sk-ant-api03-secret"
      })

    assert error_text(result) =~ "no environment with this ID"
    assert Sandboxes.list_agent_environments(account) == []
  end

  test "requires an account administrator and the sandboxes flag", %{member: member, admin: admin, handle: handle} do
    reject(&ControlPlane.get_environment/2)

    assert error_text(ListClaudeEnvironments.call(user_conn(member), %{"account_handle" => handle})) =~
             "do not have access"

    connect = %{
      "account_handle" => handle,
      "environment_id" => "env_01X",
      "environment_key" => "sk-ant-env-secret",
      "api_key" => "sk-ant-api03-secret"
    }

    assert error_text(ConnectClaudeEnvironment.call(user_conn(member), connect)) =~ "do not have access"

    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    assert error_text(ConnectClaudeEnvironment.call(user_conn(admin), connect)) =~ "not enabled"
  end

  defp error_text(%{"isError" => true, "content" => [%{"text" => text}]}), do: text
end
