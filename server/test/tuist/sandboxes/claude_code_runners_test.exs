defmodule Tuist.Sandboxes.ClaudeCodeRunnersTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.SandboxesFixtures

  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes
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
    account: account,
    agent_environment: agent_environment
  } do
    test_pid = self()
    account_id = account.id

    stub(Tuist.Environment, :runners_cluster_network_platforms, fn -> [:linux, :macos] end)

    expect(Tuist.Kura, :runner_cache_endpoint_url, fn %{id: ^account_id}, :macos, _site ->
      "http://kura-tuist.ber1.svc.cluster.local:8080"
    end)

    stub(Capacity, :admissible?, fn _environment, "session_01abc" -> true end)
    expect(Capacity, :place, fn %Sandbox{platform: :darwin, template: "macos"} -> {:ok, "mac-a"} end)
    expect(Nodes, :call, fn "mac-a", "create", _args, _opts -> {:ok, %{"boot_ms" => 19_000}} end)
    # CI closed the grant while the VM booted; the new VM already holds its slot.
    stub(Capacity, :admit_turn, fn _sandbox, _fun -> {:error, :no_capacity} end)

    expect(Nodes, :call, fn "mac-a", "start_worker", %{sandbox_id: sandbox_id, env: env}, _opts ->
      send(test_pid, {:started, sandbox_id, env})
      {:ok, %{}}
    end)

    # The longest order id the spawn endpoint accepts, with the dots it allows.
    order = %{@order | order_id: String.duplicate("o.", 127) <> "1"}
    assert {:ok, :accepted} = ClaudeCodeRunners.spawn(agent_environment, order)
    assert_receive {:started, sandbox_id, env}, 5_000

    # The macOS guest refuses a worker without a work id, and accepts only
    # [A-Za-z0-9_-]{1,255} as one.
    {work_id, env} = Map.pop(env, "ANTHROPIC_WORK_ID")
    assert work_id =~ ~r/\A[A-Za-z0-9_-]{1,255}\z/

    # Idle minutes round up, the work order travels only in the worker's
    # environment, and the sessions get the account's in-rack cache.
    assert env == %{
             "SBX_CLAUDE_CODE_WORK_ORDER" => "header.claims.signature",
             "SBX_CLAUDE_CODE_RELEASE_IDLE_MIN" => "25",
             "SBX_WORKDIR" => "/Users/runner/work",
             "TUIST_URL" => Tuist.Environment.app_url(),
             "TUIST_CACHE_ENDPOINT" => "http://kura-tuist.ber1.svc.cluster.local:8080"
           }

    assert %Sandbox{platform: :darwin, anthropic_session_id: "session_01abc", residency_work_id: ^work_id} =
             Repo.get(Sandbox, sandbox_id)
  end

  test "a session of a GitHub repository starts its runner with the repository's checkout volume", %{
    agent_environment: agent_environment
  } do
    test_pid = self()
    stub(Capacity, :admissible?, fn _environment, _session -> true end)
    stub(Capacity, :admit_turn, fn _sandbox, fun -> fun.() end)
    stub(Capacity, :place, fn _sandbox -> {:ok, "mac-a"} end)

    expect(CacheVolumes, :allocate_sandbox_checkout, fn %Sandbox{node_name: "mac-a"}, "acme/app", work_id ->
      assert work_id =~ ~r/\Aclaude-code-/

      {:ok,
       %{
         id: "11111111-1111-4111-8111-111111111111",
         account_id: 1,
         scope: String.duplicate("a", 64),
         generation: 1,
         base_generation: 2,
         image_digest: nil,
         content_digest: nil,
         uid: 502,
         can_publish: false,
         repository: "acme/app",
         clone_url: "https://github.com/acme/app",
         default_branch: "main",
         commit: String.duplicate("c", 40),
         default_branch_job: true,
         may_start_master: false,
         volume_key: String.duplicate("d", 64)
       }}
    end)

    stub(Nodes, :call, fn
      "mac-a", "create", _args, _opts -> {:ok, %{}}
      "mac-a", "start_worker", args, _opts -> send(test_pid, {:start_worker, args}) && {:ok, %{}}
    end)

    order = Map.put(@order, :repository_url, "https://github.com/acme/app.git")
    assert {:ok, :accepted} = ClaudeCodeRunners.spawn(agent_environment, order)
    assert_receive {:start_worker, %{checkout: checkout}}, 5_000

    # The guest keeps the repository where the runner clones it; the host gets
    # only what it needs to seed and collect, never the account.
    assert checkout.path == "/Users/runner/work/claude-code/acme/app"
    assert checkout.commit == String.duplicate("c", 40)
    refute Map.has_key?(checkout, :account_id)
    refute Map.has_key?(checkout, :repository)
  end

  test "a session whose repository has no checkout starts its runner without one", %{
    agent_environment: agent_environment
  } do
    test_pid = self()
    stub(Capacity, :admissible?, fn _environment, _session -> true end)
    stub(Capacity, :admit_turn, fn _sandbox, fun -> fun.() end)
    stub(Capacity, :place, fn _sandbox -> {:ok, "mac-a"} end)
    stub(CacheVolumes, :allocate_sandbox_checkout, fn _sandbox, _repository, _work_id -> {:error, :unavailable} end)

    stub(Nodes, :call, fn
      "mac-a", "create", _args, _opts -> {:ok, %{}}
      "mac-a", "start_worker", args, _opts -> send(test_pid, {:start_worker, args}) && {:ok, %{}}
    end)

    order = Map.put(@order, :repository_url, "https://github.com/acme/private")
    assert {:ok, :accepted} = ClaudeCodeRunners.spawn(agent_environment, order)
    assert_receive {:start_worker, args}, 5_000
    refute Map.has_key?(args, :checkout)
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
