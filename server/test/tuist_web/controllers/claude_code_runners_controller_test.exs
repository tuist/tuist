defmodule TuistWeb.ClaudeCodeRunnersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Kubernetes.Client
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.ClaudeCodeRuntime

  setup do
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)

    agent_environment =
      agent_environment_fixture(kind: :claude_code, anthropic_environment_id: "ccpool_01linux", max_idle_seconds: 1800)

    %{agent_environment: agent_environment}
  end

  @body %{"order_id" => "order-1", "session_id" => "session_01abc", "work_order" => "header.claims.signature"}

  defp identity(name, namespace \\ "tuist-amp-orbs") do
    stub(Client, :create_claude_code_provider_token_review, fn "workload" ->
      {:ok, %{namespace: namespace, name: name, uid: "sa-id"}}
    end)
  end

  defp spawn_request(conn, body \\ @body) do
    conn |> put_req_header("authorization", "Bearer workload") |> post("/api/internal/claude-code-runners/spawn", body)
  end

  test "the workload identity alone picks the environment", %{conn: conn, agent_environment: agent_environment} do
    managed_agents = agent_environment_fixture()
    reject(&Capacity.admissible?/2)

    identity(ClaudeCodeRuntime.name(managed_agents))
    assert conn |> spawn_request() |> response(:unauthorized)

    identity(ClaudeCodeRuntime.name(agent_environment), "default")
    assert build_conn() |> spawn_request() |> response(:unauthorized)

    identity("amp-" <> String.duplicate("0", 32) <> "-1")
    assert build_conn() |> spawn_request() |> response(:unauthorized)
  end

  test "a malformed request is refused for good", %{conn: conn, agent_environment: agent_environment} do
    identity(ClaudeCodeRuntime.name(agent_environment))
    reject(&Capacity.admissible?/2)

    assert conn |> spawn_request(%{@body | "work_order" => "not a jwt"}) |> response(:bad_request)
    assert build_conn() |> spawn_request(Map.delete(@body, "session_id")) |> response(:bad_request)
  end

  test "a session that does not fit asks the orchestrator to retry", %{conn: conn, agent_environment: agent_environment} do
    identity(ClaudeCodeRuntime.name(agent_environment))
    stub(Capacity, :admissible?, fn %{id: id}, "session_01abc" when id == agent_environment.id -> false end)

    assert conn |> spawn_request() |> response(:too_many_requests)
  end
end
