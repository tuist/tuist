defmodule Tuist.Sandboxes.ClaudeCodeRunners do
  @moduledoc """
  Starts the Claude Code runner of one cloud session in the session's sandbox.

  A `:claude_code` agent environment's orchestrator hands each spawn request
  (a session with no runner) to `spawn/2`. The answer comes before the VM boots,
  so the orchestrator's hook stays inside its timeout: a session whose sandbox
  already holds a residency has its runner on the way (`:running`); one that
  fits is `:accepted`, and its sandbox is created or resumed and `sbx-worker`
  started with the work order on a supervised task; one that does not fit is
  refused with `:no_capacity` and re-requested by the orchestrator after
  backoff. A work order the task fails to start is re-requested by Anthropic
  once the orchestrator's lease runs out.

  The session's sandbox runs the environment's platform. When the session's
  primary repository is a github.com repository the account's GitHub
  installation reads, the runner starts with the repository's checkout volume,
  the one its CI jobs use (`Tuist.Runners.CacheVolumes.allocate_sandbox_checkout/3`):
  a new sandbox copies the node's master of it to where the runner keeps its
  clone, so the runner fetches only what changed, and the session's export feeds
  the master back under CI's rules. The runner exits
  after the session has been idle for the environment's `max_idle_seconds`,
  which ends the residency and pauses the sandbox; the session's next message
  resumes the same sandbox, checkout included.
  """
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Anthropic.Supervisor, as: AnthropicSupervisor
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Router
  alias Tuist.Sandboxes.Sandbox

  require Logger

  @prepared_workspace_seconds 6 * 60 * 60

  def spawn(%AgentEnvironment{kind: :claude_code} = agent_environment, %{session_id: session_id} = order) do
    received_at = System.monotonic_time()
    agent_environment = Repo.preload(agent_environment, :account)

    result =
      if agent_environment.enabled and FeatureFlags.sandboxes_enabled?(agent_environment.account) do
        case Sandboxes.get_sandbox_for_session(agent_environment.id, session_id) do
          %Sandbox{residency_work_id: work_id} when is_binary(work_id) ->
            {:ok, :running}

          %Sandbox{platform: :darwin, state: :error} ->
            {:error, :sandbox_recovery_required}

          _sandbox ->
            admit(agent_environment, Map.put(order, :received_at, received_at))
        end
      else
        {:error, :disabled}
      end

    # The request log samples successful responses, so this line is what times
    # a session's spawn request: it is logged when the answer is ready, and
    # duration_ms is the admission time since the request reached this module.
    Logger.info("sandboxes: claude code spawn request",
      agent_environment_id: agent_environment.id,
      session_id: session_id,
      spawn_result: result |> elem(1) |> to_string(),
      duration_ms: milliseconds_since(received_at)
    )

    result
  end

  defp admit(agent_environment, order) do
    if Capacity.admissible?(agent_environment, order.session_id) do
      {:ok, _pid} =
        Task.Supervisor.start_child(AnthropicSupervisor.task_supervisor(), fn ->
          start_runner(agent_environment, order)
        end)

      {:ok, :accepted}
    else
      {:error, :no_capacity}
    end
  end

  @doc false
  def start_runner(agent_environment, %{order_id: order_id, session_id: session_id, work_order: work_order} = order) do
    # A macOS guest accepts only [A-Za-z0-9_-]{1,255} as a work id, and an
    # order id may hold dots and be 255 characters long. A hash stays stable
    # across re-requests of the same order.
    work_id = "claude-code-" <> (:sha256 |> :crypto.hash(order_id) |> Base.encode16(case: :lower) |> binary_part(0, 32))

    repository = repository(Map.get(order, :repository_url))

    started_at = System.monotonic_time()

    # A re-request while an earlier one still boots the VM finds the lock taken.
    result =
      Sandboxes.with_sandbox_lock(
        "claude-code:#{agent_environment.id}:#{session_id}",
        fn ->
          with {:ok, sandbox, created?} <-
                 Router.find_or_create_sandbox(agent_environment, session_id,
                   prefer_nodes: checkout_nodes(agent_environment, repository)
                 ),
               placement_ms = milliseconds_since(started_at),
               {:ok, sandbox} <- Sandboxes.prepare_residency(sandbox, work_id, created: created?),
               {:ok, _data} <-
                 Router.start_worker(
                   sandbox,
                   worker_env(agent_environment, sandbox, work_id, work_order),
                   checkout(sandbox, repository, work_id)
                 ) do
            {:ok, sandbox, placement_ms}
          end
        end,
        wait: false
      )

    case result do
      # placement_ms covers placing the sandbox (with any carve-out growth it
      # waits for) and creating or resuming its VM; spawn_ms runs from the
      # spawn request to the started worker.
      {:ok, sandbox, placement_ms} ->
        Logger.info("sandboxes: claude code runner started",
          sandbox_id: sandbox.id,
          node: sandbox.node_name,
          agent_environment_id: agent_environment.id,
          session_id: session_id,
          placement_ms: placement_ms,
          spawn_ms: milliseconds_since(Map.get(order, :received_at, started_at))
        )

        {:ok, sandbox}

      {:error, reason} = error ->
        Logger.warning("sandboxes: claude code runner not started",
          agent_environment_id: agent_environment.id,
          session_id: session_id,
          reason: inspect(reason)
        )

        error
    end
  end

  defp milliseconds_since(monotonic_time),
    do: System.convert_time_unit(System.monotonic_time() - monotonic_time, :native, :millisecond)

  # The runner's checkout directory names come from the URL, so only exact
  # `https://github.com/<owner>/<repo>` URLs name a checkout.
  @github_url ~r"\Ahttps://github\.com/([A-Za-z0-9][A-Za-z0-9-]{0,38})/([A-Za-z0-9._-]{1,100}?)(?:\.git)?/?\z"

  defp repository(url) when is_binary(url) do
    case Regex.run(@github_url, url) do
      [_url, owner, name] when name not in [".", ".."] -> %{owner: owner, name: name}
      _ -> nil
    end
  end

  defp repository(_url), do: nil

  # A new Linux sandbox goes first to a node where one of the account's
  # sandboxes recently used the repository's checkout: that node holds its
  # master and, while sandboxd keeps it (CHECKOUT_WORKSPACES_TTL, 6 hours),
  # the workspace prepared from that seed, which the guest starts from
  # instead of copying the tree.
  defp checkout_nodes(%AgentEnvironment{platform: :linux, account_id: account_id}, %{owner: owner, name: name}) do
    since = DateTime.add(DateTime.utc_now(), -@prepared_workspace_seconds, :second)
    CacheVolumes.recent_sandbox_checkout_nodes(account_id, "#{owner}/#{name}", "linux", since)
  end

  defp checkout_nodes(_agent_environment, _repository), do: []

  # The session's checkout grant, or nil: a session without one clones.
  defp checkout(_sandbox, nil, _work_id), do: nil

  defp checkout(sandbox, %{owner: owner, name: name}, work_id) do
    case CacheVolumes.allocate_sandbox_checkout(sandbox, "#{owner}/#{name}", work_id) do
      {:ok, allocation} ->
        allocation
        |> Map.take(
          ~w(id scope generation base_generation image_digest content_digest uid clone_url default_branch commit default_branch_job may_start_master volume_key)a
        )
        |> Map.put(:path, Path.join([Sandboxes.workspace(sandbox), "claude-code", owner, name]))

      {:error, _reason} ->
        nil
    end
  end

  # A macOS host refuses a worker without ANTHROPIC_WORK_ID: it records the id
  # as the sandbox's worker so a retried start cannot run a second one. The
  # runner and its sessions inherit the Tuist environment; sbx-worker hands
  # each session's identity token to the Tuist clients, which exchange it
  # (`Tuist.OIDC`), so the guest itself holds no Tuist credential.
  defp worker_env(agent_environment, sandbox, work_id, work_order) do
    %{account: account} = Repo.preload(agent_environment, :account)

    env =
      Map.merge(Sandboxes.tuist_env(account, sandbox), %{
        "ANTHROPIC_WORK_ID" => work_id,
        "SBX_CLAUDE_CODE_WORK_ORDER" => work_order,
        "SBX_CLAUDE_CODE_RELEASE_IDLE_MIN" => to_string(max(div(agent_environment.max_idle_seconds + 59, 60), 1))
      })

    if sandbox.platform == :darwin, do: Map.put(env, "SBX_WORKDIR", Sandboxes.workspace(sandbox)), else: env
  end
end
