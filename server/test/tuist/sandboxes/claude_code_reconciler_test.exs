defmodule Tuist.Sandboxes.ClaudeCodeReconcilerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Kubernetes.Client
  alias Tuist.Sandboxes.ClaudeCodeReconciler

  @config %{namespace: "providers", image: "claude-code:1", url: "https://tuist.example", node_selector: %{}}

  setup do
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    :ok
  end

  test "runs an orchestrator per enabled Claude Code environment and removes the rest" do
    enabled =
      agent_environment_fixture(
        kind: :claude_code,
        anthropic_environment_id: "ccpool_01on",
        environment_key: "sk-ant-cc-on"
      )

    disabled = agent_environment_fixture(kind: :claude_code, anthropic_environment_id: "ccpool_01off", enabled: false)
    _managed_agents = agent_environment_fixture()
    test_pid = self()

    stub(Client, :get, fn path, _opts ->
      cond do
        String.contains?(path, "serviceaccounts?") ->
          {:ok,
           %{
             "items" => [
               %{"metadata" => %{"name" => "claude-code-#{enabled.id}"}},
               %{"metadata" => %{"name" => "claude-code-#{disabled.id}"}}
             ]
           }}

        String.contains?(path, "pods?") ->
          {:ok, %{"items" => []}}
      end
    end)

    expect(Client, :apply, 3, fn manifest ->
      send(test_pid, {:applied, manifest})
      {:ok, %{}}
    end)

    expect(Client, :delete, 3, fn path ->
      send(test_pid, {:deleted, path})
      :ok
    end)

    assert :ok = ClaudeCodeReconciler.reconcile(@config)

    name = "claude-code-#{enabled.id}"
    assert_received {:applied, %{"kind" => "ServiceAccount", "metadata" => %{"name" => ^name}}}
    assert_received {:applied, %{"kind" => "Secret", "data" => %{"environment-secret" => secret}}}
    assert Base.decode64!(secret) == "sk-ant-cc-on"
    assert_received {:applied, %{"kind" => "Deployment", "spec" => %{"template" => %{"spec" => pod}}}}

    assert [%{"projected" => %{"sources" => [%{"serviceAccountToken" => %{"audience" => "tuist-claude-code-runners"}}]}}] =
             Enum.filter(pod["volumes"], &(&1["name"] == "identity"))

    stale = "claude-code-#{disabled.id}"
    assert_received {:deleted, "/apis/apps/v1/namespaces/providers/deployments/" <> ^stale}
    assert_received {:deleted, "/api/v1/namespaces/providers/secrets/" <> ^stale}
    assert_received {:deleted, "/api/v1/namespaces/providers/serviceaccounts/" <> ^stale}
  end
end
