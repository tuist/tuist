defmodule Tuist.Sandboxes do
  @moduledoc """
  Control plane for Firecracker sandboxes (see `infra/sandboxd/AGENTS.md`).

  Owns the `sandboxes`, `sandbox_agent_environments` and
  `sandbox_agent_sessions` tables and drives the sandboxd nodes through
  `Tuist.Sandboxes.Nodes`. Every state transition here mirrors one node
  command: `create`, `resume`, `pause`, `delete`, `exec`, `start_worker`.
  Node-originated changes arrive as events (`worker_exited`,
  `sandbox_died`) and periodic reports, which reconcile what the database
  believes against what the node holds. Agent sessions started through
  Tuist are delegated to `Tuist.Sandboxes.AgentSessions`.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.AgentSessions
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.PauseSandboxWorker
  alias Tuist.Tasks

  require Logger

  @default_template "default"
  @default_shape %{vcpus: 2, memory_mb: 4096, workspace_gb: 10}
  @default_pause_grace_seconds 30
  @create_timeout to_timeout(second: 120)
  @resume_timeout to_timeout(second: 120)
  @exec_default_timeout_ms 60_000
  @exec_max_timeout_ms 600_000
  @exec_timeout_slack_ms 10_000
  @exec_output_limit_bytes 1_048_576
  @transient_node_errors [:not_connected, :node_disconnected, :timeout]
  # A row still `creating` or `resuming` this long after its last update
  # belongs to a caller that died mid-operation (a web pod stopped during a
  # deploy): the node's report decides what it is now.
  @stuck_after_seconds 150
  @max_live_sandboxes_per_account 50
  @live_states [:creating, :running, :resuming, :paused]

  def default_template, do: @default_template
  def default_shape, do: @default_shape

  # ----- Agent environments -----

  def create_agent_environment(%Account{id: account_id}, attrs) when is_map(attrs) do
    %AgentEnvironment{}
    |> AgentEnvironment.create_changeset(Map.put(attrs, :account_id, account_id))
    |> Repo.insert()
  end

  def list_agent_environments(%Account{id: account_id}) do
    Repo.all(from e in AgentEnvironment, where: e.account_id == ^account_id, order_by: [asc: e.id])
  end

  def list_enabled_agent_environments do
    Repo.all(from e in AgentEnvironment, where: e.enabled == true, order_by: [asc: e.id], preload: [:account])
  end

  def get_agent_environment(%Account{id: account_id}, id) do
    case Repo.get_by(AgentEnvironment, id: id, account_id: account_id) do
      nil -> {:error, :not_found}
      agent_environment -> {:ok, agent_environment}
    end
  end

  def get_agent_environment_by_id(id) do
    case Repo.get(AgentEnvironment, id) do
      nil -> {:error, :not_found}
      agent_environment -> {:ok, agent_environment}
    end
  end

  def update_agent_environment(%AgentEnvironment{} = agent_environment, attrs) when is_map(attrs) do
    agent_environment
    |> AgentEnvironment.update_changeset(attrs)
    |> Repo.update()
  end

  # ----- Agent sessions -----

  defdelegate start_agent_session(account, attrs, opts \\ []), to: AgentSessions
  defdelegate list_agent_sessions(account), to: AgentSessions
  defdelegate get_agent_session(account, id), to: AgentSessions
  defdelegate get_agent_session!(account, id), to: AgentSessions
  defdelegate refresh_agent_session(agent_session), to: AgentSessions
  defdelegate send_agent_session_message(agent_session, text), to: AgentSessions
  defdelegate list_agent_session_events(agent_session, opts \\ []), to: AgentSessions
  defdelegate archive_agent_session(agent_session), to: AgentSessions

  @doc """
  Deletes the environment and, best effort, every sandbox created for its
  sessions. A sandbox whose node refuses the delete stays behind in the
  error state (with its `agent_environment_id` nilified by the FK) so an
  operator can retry it from the account API.
  """
  def delete_agent_environment(%AgentEnvironment{} = agent_environment) do
    Sandbox
    |> where([s], s.agent_environment_id == ^agent_environment.id)
    |> Repo.all()
    |> Enum.each(fn sandbox ->
      case delete(sandbox) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("sandboxes: failed to delete sandbox while deleting its agent environment",
            sandbox_id: sandbox.id,
            agent_environment_id: agent_environment.id,
            reason: inspect(reason)
          )
      end
    end)

    Repo.delete(agent_environment)
  end

  # ----- Sandboxes -----

  def list_sandboxes(%Account{id: account_id}) do
    Repo.all(
      from s in Sandbox,
        where: s.account_id == ^account_id and s.state != ^:deleted,
        order_by: [desc: s.inserted_at, desc: s.id]
    )
  end

  @doc """
  Sandboxes paused, or errored, since before `cutoff`: both still hold
  their disk on the node until deleted. A sandbox the node reported as
  paused without the server pausing it has no `paused_at`; its last
  update stands in.
  """
  def list_sandboxes_idle_before(%DateTime{} = cutoff) do
    Repo.all(
      from s in Sandbox,
        where:
          (s.state == :paused and coalesce(s.paused_at, s.updated_at) < ^cutoff) or
            (s.state == :error and s.updated_at < ^cutoff),
        order_by: [asc: s.updated_at]
    )
  end

  def get_sandbox(%Account{id: account_id}, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Sandbox{} = sandbox <- Repo.get_by(Sandbox, id: uuid, account_id: account_id) do
      {:ok, sandbox}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_sandbox!(%Account{} = account, id) do
    case get_sandbox(account, id) do
      {:ok, sandbox} -> sandbox
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Sandbox
    end
  end

  def get_sandbox_by_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Sandbox, uuid)
      :error -> nil
    end
  end

  def get_sandbox_for_session(agent_environment_id, session_id)
      when is_integer(agent_environment_id) and is_binary(session_id) do
    Repo.get_by(Sandbox, agent_environment_id: agent_environment_id, anthropic_session_id: session_id)
  end

  @doc """
  Inserts the sandbox row, picks a node that has the template ready and
  boots the VM there. The row exists before the node hears about the id,
  so a report that races the create never looks like an orphan.
  """
  def create_sandbox(%Account{id: account_id}, attrs \\ %{}) when is_map(attrs) do
    attrs =
      @default_shape
      |> Map.put(:template, @default_template)
      |> Map.merge(attrs |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new())
      |> Map.put(:account_id, account_id)

    with :ok <- check_sandbox_limit(account_id),
         {:ok, sandbox} <- %Sandbox{} |> Sandbox.create_changeset(attrs) |> Repo.insert() do
      boot(sandbox)
    end
  end

  def max_live_sandboxes_per_account, do: @max_live_sandboxes_per_account

  defp check_sandbox_limit(account_id) do
    live = Repo.aggregate(from(s in Sandbox, where: s.account_id == ^account_id and s.state in ^@live_states), :count)
    if live < @max_live_sandboxes_per_account, do: :ok, else: {:error, :sandbox_limit}
  end

  defp boot(%Sandbox{} = sandbox) do
    hostname = "sbx-" <> String.slice(sandbox.id, 0, 8)

    args = %{
      sandbox_id: sandbox.id,
      template: sandbox.template,
      vcpus: sandbox.vcpus,
      memory_mb: sandbox.memory_mb,
      workspace_gb: sandbox.workspace_gb,
      hostname: hostname
    }

    with {:ok, node_name} <- Capacity.place(sandbox),
         {:ok, data} <- Nodes.call(node_name, "create", args, timeout: @create_timeout) do
      Logger.info("sandboxes: sandbox created",
        sandbox_id: sandbox.id,
        node: node_name,
        template: sandbox.template,
        boot_ms: data["boot_ms"]
      )

      sandbox
      |> update_sandbox(%{
        state: :running,
        node_name: node_name,
        hostname: hostname,
        template_tag: data["template_tag"],
        last_active_at: now(),
        error_message: nil
      })
      |> schedule_idle_pause()
    else
      {:error, reason} ->
        Logger.warning("sandboxes: sandbox creation failed", sandbox_id: sandbox.id, reason: inspect(reason))
        {:ok, _} = update_sandbox(sandbox, %{state: :error, hostname: hostname, error_message: error_message(reason)})
        {:error, reason}
    end
  end

  @doc """
  Runs `fun` while holding the cluster-wide lock of one sandbox, so the
  lifecycle transitions different processes and replicas issue for the
  same sandbox (the next turn's resume, the pause after its grace period,
  a reclaim, an API call) happen one at a time against a fresh row.
  `wait: false` answers `{:error, :locked}` instead of waiting; callers
  that already hold another sandbox's lock must use it, so two of them
  never wait on each other. Never call this from a node's socket process:
  the node commands issued under the lock are answered through it.
  """
  def with_sandbox_lock(sandbox_id, fun, opts \\ []) when is_binary(sandbox_id) and is_function(fun, 0) do
    retries = if Keyword.get(opts, :wait, true), do: :infinity, else: 0

    case :global.trans({{__MODULE__, sandbox_id}, self()}, fun, [node() | Node.list()], retries) do
      :aborted -> {:error, :locked}
      result -> result
    end
  end

  def ensure_running(%Sandbox{state: :running} = sandbox), do: {:ok, sandbox}

  def ensure_running(%Sandbox{state: :paused, id: id}) do
    with_sandbox_lock(id, fn -> with_fresh(id, &running_or_resume/1) end)
  end

  def ensure_running(%Sandbox{state: state}), do: {:error, {:invalid_state, state}}

  def resume(%Sandbox{id: id}) do
    with_sandbox_lock(id, fn ->
      with_fresh(id, fn
        %Sandbox{state: :paused} = sandbox -> do_resume(sandbox)
        %Sandbox{state: state} -> {:error, {:invalid_state, state}}
      end)
    end)
  end

  @doc """
  Makes the session's sandbox run and records the residency of `work_id`
  in one step under the sandbox's lock, so a scheduled pause cannot slip
  between the resume and the residency that keeps it running.
  """
  def prepare_residency(%Sandbox{id: id}, work_id) when is_binary(work_id) do
    with_sandbox_lock(id, fn ->
      with_fresh(id, fn sandbox ->
        with {:ok, sandbox} <- running_or_resume(sandbox) do
          begin_residency(sandbox, work_id)
        end
      end)
    end)
  end

  defp with_fresh(id, fun) do
    case get_sandbox_by_id(id) do
      %Sandbox{} = sandbox -> fun.(sandbox)
      nil -> {:error, :not_found}
    end
  end

  defp running_or_resume(%Sandbox{state: :running} = sandbox), do: {:ok, sandbox}
  defp running_or_resume(%Sandbox{state: :paused} = sandbox), do: do_resume(sandbox)
  defp running_or_resume(%Sandbox{state: state}), do: {:error, {:invalid_state, state}}

  defp do_resume(%Sandbox{state: :paused, node_name: node_name} = sandbox) when is_binary(node_name) do
    with {:ok, sandbox} <- Capacity.admit(sandbox) do
      case Nodes.call(node_name, "resume", %{sandbox_id: sandbox.id}, timeout: @resume_timeout) do
        {:ok, data} ->
          Logger.info("sandboxes: sandbox resumed",
            sandbox_id: sandbox.id,
            node: node_name,
            restore_ms: data["restore_ms"]
          )

          sandbox
          |> update_sandbox(%{state: :running, paused_at: nil, last_active_at: now(), error_message: nil})
          |> schedule_idle_pause()

        # The snapshot is intact on the node's disk; a node that is away or
        # slow is not a reason to give the sandbox up.
        {:error, reason} when reason in @transient_node_errors ->
          {:ok, _} = update_sandbox(sandbox, %{state: :paused})
          {:error, reason}

        {:error, reason} ->
          {:ok, _} = update_sandbox(sandbox, %{state: :error, error_message: error_message(reason)})
          {:error, reason}
      end
    end
  end

  defp do_resume(%Sandbox{state: :paused}), do: {:error, :no_node}

  def pause(%Sandbox{id: id}) do
    with_sandbox_lock(id, fn ->
      with_fresh(id, fn
        %Sandbox{state: :running} = sandbox -> do_pause(sandbox)
        %Sandbox{state: state} -> {:error, {:invalid_state, state}}
      end)
    end)
  end

  @doc """
  Pauses the sandbox only if it is still running with no residency (and,
  with `:residency_epoch`, only if no residency started or ended since
  that epoch), checked against the row under the sandbox's lock. Answers
  `{:ok, :skipped}` when the sandbox is no longer idle. `wait: false`
  skips a sandbox whose lock is held, which is how a reclaim running
  under another sandbox's lock avoids waiting on it.
  """
  def pause_idle(sandbox_id, opts \\ []) when is_binary(sandbox_id) do
    epoch = Keyword.get(opts, :residency_epoch)

    with_sandbox_lock(
      sandbox_id,
      fn ->
        with_fresh(sandbox_id, fn
          %Sandbox{state: :running, residency_work_id: nil} = sandbox
          when is_nil(epoch) or sandbox.residency_epoch == epoch ->
            do_pause(sandbox)

          %Sandbox{} ->
            {:ok, :skipped}
        end)
      end,
      wait: Keyword.get(opts, :wait, true)
    )
  end

  defp do_pause(%Sandbox{state: :running, node_name: node_name} = sandbox) when is_binary(node_name) do
    case Nodes.call(node_name, "pause", %{sandbox_id: sandbox.id}, []) do
      {:ok, data} ->
        Logger.info("sandboxes: sandbox paused",
          sandbox_id: sandbox.id,
          node: node_name,
          snapshot_ms: data["snapshot_ms"],
          mem_bytes: data["mem_bytes"]
        )

        update_sandbox(sandbox, %{state: :paused, paused_at: now()})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_pause(%Sandbox{state: :running}), do: {:error, :no_node}

  @doc """
  Tears the VM down on its node and removes the row. The row flips to
  `deleted` first so a concurrent report ignores it, and a node that is
  not connected does not block the delete: the orphaned jail directory
  is removed when the node's next report lists a sandbox we no longer
  know.
  """
  def delete(%Sandbox{id: id} = sandbox) do
    with_sandbox_lock(id, fn ->
      sandbox = get_sandbox_by_id(id) || sandbox

      with {:ok, sandbox} <- update_sandbox(sandbox, %{state: :deleted, residency_work_id: nil}),
           :ok <- delete_on_node(sandbox) do
        Repo.delete(sandbox)
      else
        {:error, reason} ->
          {:ok, _} = update_sandbox(sandbox, %{state: :error, error_message: error_message(reason)})
          {:error, reason}
      end
    end)
  end

  defp delete_on_node(%Sandbox{node_name: nil}), do: :ok

  defp delete_on_node(%Sandbox{node_name: node_name} = sandbox) do
    case Nodes.call(node_name, "delete", %{sandbox_id: sandbox.id}, []) do
      {:ok, _data} -> :ok
      {:error, :not_connected} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs `cmd` (an argv list) inside the sandbox, resuming it first when it
  is paused, and returns the exit code with the collected output. Output
  is capped at 1 MiB per stream.

  Options: `:timeout_ms` (default 60s, max 10min), `:env`, `:cwd`.
  """
  def exec(%Sandbox{} = sandbox, cmd, opts \\ []) when is_list(cmd) do
    timeout_ms =
      opts
      |> Keyword.get(:timeout_ms, @exec_default_timeout_ms)
      |> max(1)
      |> min(@exec_max_timeout_ms)

    case ensure_running(sandbox) do
      {:ok, %Sandbox{node_name: node_name} = sandbox} when is_binary(node_name) ->
        args = %{
          sandbox_id: sandbox.id,
          cmd: cmd,
          env: Keyword.get(opts, :env, %{}),
          cwd: Keyword.get(opts, :cwd, "/workspace"),
          timeout_ms: timeout_ms
        }

        ref = make_ref()
        caller = self()
        on_stream = fn {stream, data} -> capture_output(caller, ref, stream, data) end

        result =
          Nodes.call(node_name, "exec", args, timeout: timeout_ms + @exec_timeout_slack_ms, on_stream: on_stream)

        {stdout, stderr} = drain_output(ref)
        Process.delete({ref, :stdout})
        Process.delete({ref, :stderr})
        record_activity(sandbox)

        case result do
          {:ok, data} when is_map(data) ->
            {:ok, %{exit_code: data["exit_code"], stdout: stdout, stderr: stderr}}

          {:ok, _data} ->
            {:ok, %{exit_code: nil, stdout: stdout, stderr: stderr}}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %Sandbox{}} ->
        {:error, :no_node}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # `on_stream` runs in the calling process for every frame, so the cap
  # is applied there, before anything reaches the mailbox: output past
  # the limit is dropped as it arrives instead of piling up until the
  # call returns.
  defp capture_output(caller, ref, stream, data) do
    key = {ref, stream}
    size = Process.get(key, 0)
    room = @exec_output_limit_bytes - size

    if room > 0 do
      chunk = if byte_size(data) > room, do: binary_part(data, 0, room), else: data
      Process.put(key, size + byte_size(chunk))
      send(caller, {ref, stream, chunk})
    end
  end

  # Everything for `ref` is already queued once the call returns, so a
  # non-blocking drain collects it all. Output is bytes; the API returns
  # strings, so invalid UTF-8 (binary output, or a cut through a
  # multi-byte character) is replaced.
  defp drain_output(ref, stdout \\ [], stderr \\ []) do
    receive do
      {^ref, :stdout, data} -> drain_output(ref, [stdout, data], stderr)
      {^ref, :stderr, data} -> drain_output(ref, stdout, [stderr, data])
    after
      0 ->
        {stdout |> IO.iodata_to_binary() |> String.replace_invalid(),
         stderr |> IO.iodata_to_binary() |> String.replace_invalid()}
    end
  end

  def start_worker(%Sandbox{state: :running, node_name: node_name} = sandbox, env)
      when is_binary(node_name) and is_map(env) do
    Nodes.call(node_name, "start_worker", %{sandbox_id: sandbox.id, env: env}, [])
  end

  def start_worker(%Sandbox{state: :running}, _env), do: {:error, :no_node}
  def start_worker(%Sandbox{state: state}, _env), do: {:error, {:invalid_state, state}}

  def stop_worker(%Sandbox{state: :running, node_name: node_name} = sandbox) when is_binary(node_name) do
    Nodes.call(node_name, "stop_worker", %{sandbox_id: sandbox.id}, [])
  end

  def stop_worker(%Sandbox{state: :running}), do: {:error, :no_node}
  def stop_worker(%Sandbox{state: state}), do: {:error, {:invalid_state, state}}

  # ----- Residencies -----

  @doc """
  Records the residency of `work_id` on a running sandbox. The epoch is
  incremented in SQL so a residency ending concurrently (its
  `worker_exited` arrives on the node's socket process) never loses an
  increment.
  """
  def begin_residency(%Sandbox{id: id}, work_id) when is_binary(work_id) do
    timestamp = now()

    query = from(s in Sandbox, where: s.id == ^id and s.state == :running, select: s)

    case Repo.update_all(query,
           set: [residency_work_id: work_id, last_active_at: timestamp, updated_at: timestamp],
           inc: [residency_epoch: 1]
         ) do
      {1, [sandbox]} -> {:ok, sandbox}
      {0, []} -> {:error, :not_running}
    end
  end

  @doc """
  Clears the residency, bumps the epoch and schedules the pause that
  follows the grace period. The bump is what lets the scheduled job
  recognise that a newer residency started after it was enqueued.
  """
  def end_residency(%Sandbox{id: id} = sandbox) do
    timestamp = now()
    query = from(s in Sandbox, where: s.id == ^id and s.state != :deleted, select: s)

    case Repo.update_all(query,
           set: [residency_work_id: nil, last_active_at: timestamp, updated_at: timestamp],
           inc: [residency_epoch: 1]
         ) do
      {1, [updated]} ->
        with {:ok, _job} <- schedule_pause(updated), do: {:ok, updated}

      {0, []} ->
        {:ok, sandbox}
    end
  end

  # A sandbox left running without a residency (created or resumed
  # through the API, or used by an exec) is paused once it has been idle
  # for the grace period, as one is after a residency ends. Each new use
  # replaces the pending pause, and a residency starting meanwhile bumps
  # the epoch, which turns the pending pause into a no-op.
  defp schedule_idle_pause({:ok, %Sandbox{} = sandbox}) do
    schedule_idle_pause(sandbox)
    {:ok, sandbox}
  end

  defp schedule_idle_pause({:error, _reason} = error), do: error

  defp schedule_idle_pause(%Sandbox{state: :running, residency_work_id: nil} = sandbox) do
    case schedule_pause(sandbox) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: could not schedule the idle pause", sandbox_id: sandbox.id, reason: inspect(reason))
        :ok
    end
  end

  defp schedule_idle_pause(%Sandbox{}), do: :ok

  defp record_activity(%Sandbox{id: id}) do
    timestamp = now()
    query = from(s in Sandbox, where: s.id == ^id and s.state == :running, select: s)

    case Repo.update_all(query, set: [last_active_at: timestamp, updated_at: timestamp]) do
      {1, [sandbox]} -> schedule_idle_pause(sandbox)
      {0, []} -> :ok
    end
  end

  defp schedule_pause(%Sandbox{} = sandbox) do
    %{sandbox_id: sandbox.id, residency_epoch: sandbox.residency_epoch}
    |> PauseSandboxWorker.new(
      schedule_in: pause_grace_seconds(sandbox),
      replace: [scheduled: [:args, :scheduled_at], available: [:args, :scheduled_at]]
    )
    |> Oban.insert()
  end

  defp pause_grace_seconds(%Sandbox{agent_environment_id: nil}), do: @default_pause_grace_seconds

  defp pause_grace_seconds(%Sandbox{agent_environment_id: agent_environment_id}) do
    case Repo.get(AgentEnvironment, agent_environment_id) do
      %AgentEnvironment{pause_grace_seconds: seconds} when is_integer(seconds) -> seconds
      _ -> @default_pause_grace_seconds
    end
  end

  # ----- Node events and reports -----

  def handle_node_event(node_name, %{"event" => "worker_exited", "sandbox_id" => sandbox_id} = event) do
    case get_sandbox_by_id(sandbox_id) do
      %Sandbox{state: state} = sandbox when state != :deleted ->
        Logger.info("sandboxes: worker exited",
          sandbox_id: sandbox.id,
          node: node_name,
          exit_code: event["exit_code"],
          duration_ms: event["duration_ms"]
        )

        {:ok, _sandbox} = end_residency(sandbox)
        :ok

      _ ->
        :ok
    end
  end

  def handle_node_event(node_name, %{"event" => "sandbox_died", "sandbox_id" => sandbox_id} = event) do
    case get_sandbox_by_id(sandbox_id) do
      %Sandbox{state: state} = sandbox when state != :deleted ->
        Logger.warning("sandboxes: sandbox died", sandbox_id: sandbox.id, node: node_name, reason: event["reason"])
        mark_error(sandbox.id, event["reason"] || "sandbox died")
        :ok

      _ ->
        :ok
    end
  end

  def handle_node_event(node_name, %{"event" => "template_ready"} = event) do
    Logger.info("sandboxes: template ready", node: node_name, template: event["name"], tag: event["tag"])
    :ok
  end

  def handle_node_event(node_name, event) do
    Logger.warning("sandboxes: unknown node event", node: node_name, node_event: inspect(event))
    :ok
  end

  @doc """
  Aligns the database with a node's `hello` or `report`. Sandboxes the
  node lists take its node name and state (an `error` it reports marks
  the row errored); sandboxes we believe live on the node but it does not
  list are marked as errored; sandboxes the node lists that we no longer
  know are deleted from the node. A row left `creating` or `resuming` by a
  caller that died mid-operation is settled from the report once it has
  been stuck longer than any create or resume can take.
  """
  def reconcile_node_report(node_name, %{"sandboxes" => reported}) when is_binary(node_name) and is_list(reported) do
    reported_by_id =
      Map.new(
        for %{"id" => id} = sandbox <- reported,
            {:ok, uuid} <- [Ecto.UUID.cast(id)],
            do: {uuid, sandbox}
      )

    reported_ids = Map.keys(reported_by_id)
    known = Repo.all(from s in Sandbox, where: s.id in ^reported_ids)

    Enum.each(known, fn sandbox ->
      reconcile_reported(sandbox, node_name, Map.fetch!(reported_by_id, sandbox.id))
    end)

    reported_ids
    |> Kernel.--(Enum.map(known, & &1.id))
    |> Enum.each(&delete_orphan(node_name, &1))

    stuck_before = DateTime.add(now(), -@stuck_after_seconds, :second)

    Sandbox
    |> where([s], s.node_name == ^node_name and s.id not in ^reported_ids)
    |> where(
      [s],
      s.state in ^[:running, :paused, :resuming] or (s.state == :creating and s.updated_at < ^stuck_before)
    )
    |> Repo.all()
    |> Enum.each(fn sandbox ->
      Logger.warning("sandboxes: sandbox missing on node", sandbox_id: sandbox.id, node: node_name, state: sandbox.state)
      mark_error(sandbox.id, "missing on node", sandbox.state)
    end)

    :ok
  end

  def reconcile_node_report(_node_name, _report), do: :ok

  defp reconcile_reported(%Sandbox{state: :deleted}, _node_name, _reported), do: :ok

  defp reconcile_reported(%Sandbox{} = sandbox, _node_name, %{"state" => "error"} = reported) do
    if sandbox.state != :error do
      Logger.warning("sandboxes: node reports sandbox in error", sandbox_id: sandbox.id, reason: reported["error"])
      mark_error(sandbox.id, reported["error"] || "error on the node", sandbox.state)
    end

    :ok
  end

  defp reconcile_reported(%Sandbox{} = sandbox, node_name, reported) do
    attrs =
      %{node_name: node_name}
      |> maybe_put(:template_tag, reported["template_tag"])
      |> maybe_put_state(reported["state"])
      |> keep_in_flight_state(sandbox, reported["state"])

    if Enum.any?(attrs, fn {key, value} -> Map.get(sandbox, key) != value end) do
      {:ok, _sandbox} = update_sandbox(sandbox, attrs)
    end

    :ok
  end

  # A resume in flight holds its memory reservation through `resuming`, and
  # the node lists the sandbox as paused until the restore completes, so
  # that report must not release the reservation early, unless the resume
  # has been stuck longer than one can take (its caller died). A node that
  # already reports the sandbox running settles it either way.
  defp keep_in_flight_state(attrs, %Sandbox{state: :resuming} = sandbox, "paused") do
    if stuck?(sandbox), do: attrs, else: Map.drop(attrs, [:state, :error_message])
  end

  defp keep_in_flight_state(attrs, %Sandbox{state: :creating} = sandbox, reported_state)
       when reported_state != "running" do
    if stuck?(sandbox), do: attrs, else: Map.drop(attrs, [:state, :error_message])
  end

  defp keep_in_flight_state(attrs, _sandbox, _reported_state), do: attrs

  defp stuck?(%Sandbox{updated_at: updated_at}) do
    DateTime.diff(now(), updated_at, :second) > @stuck_after_seconds
  end

  # Errors a sandbox from outside its lock (the node's socket process must
  # never wait on one), so it only applies when the row is still in the
  # state it was read in, and the epoch is incremented in SQL.
  defp mark_error(id, message, from_state \\ nil) do
    query =
      then(from(s in Sandbox, where: s.id == ^id and s.state != :deleted), fn query ->
        if from_state, do: where(query, [s], s.state == ^from_state), else: query
      end)

    Repo.update_all(query,
      set: [state: :error, error_message: message, residency_work_id: nil, updated_at: now()],
      inc: [residency_epoch: 1]
    )

    :ok
  end

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp maybe_put_state(attrs, "running"), do: Map.merge(attrs, %{state: :running, error_message: nil})
  defp maybe_put_state(attrs, "paused"), do: Map.merge(attrs, %{state: :paused, error_message: nil})
  defp maybe_put_state(attrs, _state), do: attrs

  # Runs off the socket process: `Nodes.call/4` blocks on a message the
  # socket itself has to deliver, so calling it inline would deadlock.
  defp delete_orphan(node_name, sandbox_id) do
    Logger.warning("sandboxes: deleting sandbox unknown to the server", sandbox_id: sandbox_id, node: node_name)

    Tasks.run_async(fn ->
      case Nodes.call(node_name, "delete", %{sandbox_id: sandbox_id}, []) do
        {:ok, _data} ->
          :ok

        {:error, reason} ->
          Logger.warning("sandboxes: failed to delete orphaned sandbox",
            sandbox_id: sandbox_id,
            node: node_name,
            reason: inspect(reason)
          )
      end
    end)
  end

  # ----- Helpers -----

  defp update_sandbox(%Sandbox{} = sandbox, attrs) do
    sandbox
    |> Sandbox.update_changeset(attrs)
    |> Repo.update()
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(:no_node), do: "no node with the template ready is connected"
  defp error_message(:no_capacity), do: "no node has memory or disk left for the sandbox"
  defp error_message(:locked), do: "another operation on the sandbox is in progress"
  defp error_message(:not_connected), do: "node is not connected"
  defp error_message(:node_disconnected), do: "node disconnected during the operation"
  defp error_message(:timeout), do: "node did not answer in time"
  defp error_message(reason), do: inspect(reason)
end
