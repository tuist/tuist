defmodule Tuist.Sandboxes.ClaudeCodeRunnersTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Anthropic.Supervisor, as: AnthropicSupervisor
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.ClaudeCodeRunners
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox

  setup :set_mimic_global

  setup do
    start_supervised!({Task.Supervisor, name: AnthropicSupervisor.task_supervisor()})
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    account = account_fixture()

    agent_environment =
      agent_environment_fixture(
        account: account,
        kind: :claude_code,
        anthropic_environment_id: "ccpool_01mac",
        platform: :darwin,
        template: "macos",
        vcpus: 8,
        memory_mb: 8192,
        max_idle_seconds: 1500
      )

    %{account: account, agent_environment: agent_environment}
  end

  @order %{order_id: "order-1", session_id: "session_01abc", work_order: "header.claims.signature"}

  test "a session that fits is accepted and its runner starts in a macOS sandbox with the work order", %{
    agent_environment: agent_environment
  } do
    test_pid = self()
    stub(Capacity, :admissible?, fn _environment, "session_01abc" -> true end)
    expect(Capacity, :place, fn %Sandbox{platform: :darwin, template: "macos"} -> {:ok, "mac-a"} end)
    expect(Nodes, :call, fn "mac-a", "create", _args, _opts -> {:ok, %{"boot_ms" => 19_000}} end)
    # CI closed the grant while the VM booted; the new VM already holds its slot.
    stub(Capacity, :admit_turn, fn _sandbox, _fun -> {:error, :no_capacity} end)

    expect(Nodes, :call, fn "mac-a", "start_worker", %{sandbox_id: sandbox_id, env: env}, _opts ->
      send(test_pid, {:started, sandbox_id, env})
      {:ok, %{}}
    end)

    assert {:ok, :accepted} = ClaudeCodeRunners.spawn(agent_environment, @order)
    assert_receive {:started, sandbox_id, env}, 5_000

    # Idle minutes round up, and the work order travels only in the worker's environment.
    assert env == %{
             "SBX_CLAUDE_CODE_WORK_ORDER" => "header.claims.signature",
             "SBX_CLAUDE_CODE_RELEASE_IDLE_MIN" => "25",
             "SBX_WORKDIR" => "/Users/runner/work"
           }

    assert %Sandbox{platform: :darwin, anthropic_session_id: "session_01abc"} = Repo.get(Sandbox, sandbox_id)
  end

  test "a session whose sandbox already holds a residency answers that its runner is on the way", %{
    account: account,
    agent_environment: agent_environment
  } do
    sandbox_fixture(
      account: account,
      agent_environment_id: agent_environment.id,
      anthropic_session_id: "session_01abc",
      platform: :darwin,
      node_name: "mac-a",
      residency_work_id: "claude-code:order-0"
    )

    reject(&Capacity.admissible?/2)
    reject(&Nodes.call/4)

    assert {:ok, :running} = ClaudeCodeRunners.spawn(agent_environment, @order)
  end

  test "a session that does not fit is refused for the orchestrator to retry", %{agent_environment: agent_environment} do
    stub(Capacity, :admissible?, fn _environment, _session_id -> false end)
    reject(&Nodes.call/4)

    assert {:error, :no_capacity} = ClaudeCodeRunners.spawn(agent_environment, @order)
    assert Sandboxes.get_sandbox_for_session(agent_environment.id, "session_01abc") == nil
  end

  test "an account without sandboxes refuses the session", %{agent_environment: agent_environment} do
    stub(Tuist.FeatureFlags, :sandboxes_enabled?, fn _ -> false end)
    reject(&Capacity.admissible?/2)

    assert {:error, :disabled} = ClaudeCodeRunners.spawn(agent_environment, @order)
  end
end
