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
    Repo.all(from e in AgentEnvironment, where: e.enabled == true, order_by: [asc: e.id])
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

    with {:ok, sandbox} <- %Sandbox{} |> Sandbox.create_changeset(attrs) |> Repo.insert() do
      boot(sandbox)
    end
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

    with {:ok, node_name} <- Nodes.node_with_capacity(%{node_name: nil, template: sandbox.template}),
         {:ok, data} <- Nodes.call(node_name, "create", args, timeout: @create_timeout) do
      Logger.info("sandboxes: sandbox created",
        sandbox_id: sandbox.id,
        node: node_name,
        template: sandbox.template,
        boot_ms: data["boot_ms"]
      )

      update_sandbox(sandbox, %{
        state: :running,
        node_name: node_name,
        hostname: hostname,
        template_tag: data["template_tag"],
        last_active_at: now(),
        error_message: nil
      })
    else
      {:error, reason} ->
        Logger.warning("sandboxes: sandbox creation failed", sandbox_id: sandbox.id, reason: inspect(reason))
        {:ok, _} = update_sandbox(sandbox, %{state: :error, hostname: hostname, error_message: error_message(reason)})
        {:error, reason}
    end
  end

  def ensure_running(%Sandbox{state: :running} = sandbox), do: {:ok, sandbox}
  def ensure_running(%Sandbox{state: :paused} = sandbox), do: resume(sandbox)
  def ensure_running(%Sandbox{state: state}), do: {:error, {:invalid_state, state}}

  def resume(%Sandbox{state: :paused, node_name: node_name} = sandbox) when is_binary(node_name) do
    case Nodes.call(node_name, "resume", %{sandbox_id: sandbox.id}, timeout: @resume_timeout) do
      {:ok, data} ->
        Logger.info("sandboxes: sandbox resumed", sandbox_id: sandbox.id, node: node_name, restore_ms: data["restore_ms"])
        update_sandbox(sandbox, %{state: :running, paused_at: nil, last_active_at: now(), error_message: nil})

      # The snapshot is intact on the node's disk; a node that is away or
      # slow is not a reason to give the sandbox up.
      {:error, reason} when reason in @transient_node_errors ->
        {:error, reason}

      {:error, reason} ->
        {:ok, _} = update_sandbox(sandbox, %{state: :error, error_message: error_message(reason)})
        {:error, reason}
    end
  end

  def resume(%Sandbox{state: :paused}), do: {:error, :no_node}
  def resume(%Sandbox{state: state}), do: {:error, {:invalid_state, state}}

  def pause(%Sandbox{state: :running, node_name: node_name} = sandbox) when is_binary(node_name) do
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

  def pause(%Sandbox{state: :running}), do: {:error, :no_node}
  def pause(%Sandbox{state: state}), do: {:error, {:invalid_state, state}}

  @doc """
  Tears the VM down on its node and removes the row. The row flips to
  `deleted` first so a concurrent report ignores it, and a node that is
  not connected does not block the delete: the orphaned jail directory
  is removed when the node's next report lists a sandbox we no longer
  know.
  """
  def delete(%Sandbox{} = sandbox) do
    with {:ok, sandbox} <- update_sandbox(sandbox, %{state: :deleted, residency_work_id: nil}),
         :ok <- delete_on_node(sandbox) do
      Repo.delete(sandbox)
    else
      {:error, reason} ->
        {:ok, _} = update_sandbox(sandbox, %{state: :error, error_message: error_message(reason)})
        {:error, reason}
    end
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
        on_stream = fn {stream, data} -> send(caller, {ref, stream, data}) end

        result =
          Nodes.call(node_name, "exec", args, timeout: timeout_ms + @exec_timeout_slack_ms, on_stream: on_stream)

        {stdout, stderr} = drain_output(ref)
        _ = update_sandbox(sandbox, %{last_active_at: now()})

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

  # Stream frames were relayed to this process's mailbox by `on_stream`
  # (which runs in the caller); everything for `ref` is already queued
  # once the call returns, so a non-blocking drain collects it all.
  defp drain_output(ref, stdout \\ [], stderr \\ [], sizes \\ {0, 0}) do
    receive do
      {^ref, :stdout, data} ->
        {stdout, sizes} = append_output(stdout, data, sizes, 0)
        drain_output(ref, stdout, stderr, sizes)

      {^ref, :stderr, data} ->
        {stderr, sizes} = append_output(stderr, data, sizes, 1)
        drain_output(ref, stdout, stderr, sizes)
    after
      0 -> {IO.iodata_to_binary(stdout), IO.iodata_to_binary(stderr)}
    end
  end

  defp append_output(acc, data, sizes, index) do
    size = elem(sizes, index)
    room = @exec_output_limit_bytes - size

    cond do
      room <= 0 -> {acc, sizes}
      byte_size(data) <= room -> {[acc, data], put_elem(sizes, index, size + byte_size(data))}
      true -> {[acc, binary_part(data, 0, room)], put_elem(sizes, index, @exec_output_limit_bytes)}
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

  def begin_residency(%Sandbox{} = sandbox, work_id) when is_binary(work_id) do
    update_sandbox(sandbox, %{
      residency_work_id: work_id,
      residency_epoch: sandbox.residency_epoch + 1,
      last_active_at: now()
    })
  end

  @doc """
  Clears the residency, bumps the epoch and schedules the pause that
  follows the grace period. The bump is what lets the scheduled job
  recognise that a newer residency started after it was enqueued.
  """
  def end_residency(%Sandbox{} = sandbox) do
    with {:ok, sandbox} <-
           update_sandbox(sandbox, %{
             residency_work_id: nil,
             residency_epoch: sandbox.residency_epoch + 1,
             last_active_at: now()
           }),
         {:ok, _job} <- schedule_pause(sandbox) do
      {:ok, sandbox}
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

        {:ok, _sandbox} =
          update_sandbox(sandbox, %{
            state: :error,
            error_message: event["reason"] || "sandbox died",
            residency_work_id: nil,
            residency_epoch: sandbox.residency_epoch + 1
          })

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
  node lists take its node name and state; sandboxes we believe live on
  the node but it does not list are marked as errored; sandboxes the node
  lists that we no longer know are deleted from the node.
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

    Sandbox
    |> where([s], s.node_name == ^node_name and s.state in ^[:running, :paused])
    |> where([s], s.id not in ^reported_ids)
    |> Repo.all()
    |> Enum.each(fn sandbox ->
      Logger.warning("sandboxes: sandbox missing on node", sandbox_id: sandbox.id, node: node_name)

      {:ok, _sandbox} =
        update_sandbox(sandbox, %{
          state: :error,
          error_message: "missing on node",
          residency_work_id: nil,
          residency_epoch: sandbox.residency_epoch + 1
        })
    end)

    :ok
  end

  def reconcile_node_report(_node_name, _report), do: :ok

  defp reconcile_reported(%Sandbox{state: :deleted}, _node_name, _reported), do: :ok

  defp reconcile_reported(%Sandbox{} = sandbox, node_name, reported) do
    attrs =
      %{node_name: node_name}
      |> maybe_put(:template_tag, reported["template_tag"])
      |> maybe_put_state(reported["state"])

    if Enum.any?(attrs, fn {key, value} -> Map.get(sandbox, key) != value end) do
      {:ok, _sandbox} = update_sandbox(sandbox, attrs)
    end

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
  defp error_message(:not_connected), do: "node is not connected"
  defp error_message(:node_disconnected), do: "node disconnected during the operation"
  defp error_message(:timeout), do: "node did not answer in time"
  defp error_message(reason), do: inspect(reason)
end
