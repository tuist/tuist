defmodule Tuist.Threads.Host do
  @moduledoc """
  Hosts a thread's agent session on an `agents` node (`Tuist.Agents.Kind`).

  One process per hosted thread, started by `Tuist.Agents.Runner` under the
  thread's session lease. It takes the thread's inference runs one at a time
  (`Tuist.Threads.claim/2` at the lease epoch), queued ones and the one a
  previous host was interrupted in, and runs each in a Condukt session whose
  store is the thread's in `Tuist.Agents.SessionStore`. The
  session's journal makes an interrupted run resumable: running it again
  under its message's request id continues it where it stopped, and a Bash
  call whose command still runs in the sandbox follows that command instead
  of starting it again (its process id derives from the session and call
  ids, which do not change across hosts).

  Each run's Condukt session has its own id, `<thread id>:<run id>`, so the
  sandbox processes Bash names after it are the same for every host of a run
  and distinct across runs. The host stops only the session it started, by
  pid, never another host's by id.

  Draining hands the thread to another host and leaves its sandbox commands
  and residency alone; the run stays `running` until the next host resumes it.
  A run whose process crashes ends interrupted rather than being handed on,
  so work that crashes every host does not loop. A host that finds its run
  fenced, as when the owner lost access mid-run, exits and lets the next
  claim end the run.
  """

  @behaviour Tuist.Agents.Kind

  use GenServer, restart: :temporary

  alias Tuist.Accounts
  alias Tuist.Agents.Kind
  alias Tuist.Agents.Lease
  alias Tuist.Agents.SessionStore
  alias Tuist.Repo
  alias Tuist.Threads
  alias Tuist.Threads.Agent
  alias Tuist.Threads.MCP
  alias Tuist.Threads.Message
  alias Tuist.Threads.ModelFence
  alias Tuist.Threads.Provider
  alias Tuist.Threads.ToolLog
  alias Tuist.Threads.Workspace

  require Logger

  @supervisor Tuist.Agents.Hosts

  # Condukt's built-in tools, run in the thread's sandbox through
  # `Tuist.Threads.Sandbox`. `ToolLog` records their calls on the thread. The
  # sandbox's commands outlive this node, so Bash may follow an interrupted
  # call's command on resume.
  @repository_tools [
    Condukt.Tools.Read,
    Condukt.Tools.Glob,
    Condukt.Tools.Grep,
    Condukt.Tools.Write,
    Condukt.Tools.Edit,
    {Condukt.Tools.Bash, replay_safe: true}
  ]
  @logged_tools ["Read", "Glob", "Grep", "Write", "Edit", "Bash"]

  # A run's whole budget, then how much of it stays after the session answers,
  # to record the outcome, and after the last command it runs ends, for the
  # model to answer.
  @run_ms 3_600_000
  @finish_ms 30_000
  @answer_ms 60_000

  @impl Kind
  def start(id, epoch), do: DynamicSupervisor.start_child(@supervisor, {__MODULE__, {id, epoch}})

  @impl Kind
  def stop_if_idle(pid, reply_to, token), do: GenServer.cast(pid, {:stop_if_idle, reply_to, token})

  @impl Kind
  def drain(pid), do: GenServer.cast(pid, :drain)

  def start_link({id, epoch}), do: GenServer.start_link(__MODULE__, {id, epoch})

  @impl GenServer
  def init({id, epoch}) do
    Phoenix.PubSub.subscribe(Tuist.PubSub, Lease.topic(id))
    send(self(), :work)
    {:ok, %{id: id, epoch: epoch, task: nil, run: nil, session: nil}}
  end

  @impl GenServer
  def handle_cast({:stop_if_idle, reply_to, token}, state) do
    # One step of this process: work that arrives later finds it gone, and
    # its want keeps the thread wanted (`Tuist.Agents.Lease.release/3`).
    if is_nil(state.task) and is_nil(Threads.next_run(state.id)) do
      send(reply_to, {Kind, :idle, self(), token})
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_cast(:drain, state) do
    # Leaves parked calls and their sandbox commands for the next host.
    if state.session, do: stop_session(state.session, {:shutdown, :drain})
    if state.task, do: Task.shutdown(state.task, :brutal_kill)
    {:stop, {:shutdown, :drain}, %{state | task: nil, session: nil}}
  end

  @impl GenServer
  def handle_info(message, %{task: nil} = state) when message in [:work, {Lease, :wake}] do
    case Threads.next_run(state.id) do
      nil ->
        {:noreply, state}

      run_id ->
        case Threads.claim(run_id, state.epoch) do
          {:ok, {run, thread}} ->
            {epoch, host} = {state.epoch, self()}
            task = Task.Supervisor.async_nolink(Tuist.Threads.Tasks, fn -> execute(run, thread, epoch, host) end)

            {:noreply, %{state | task: task, run: run}}

          # A revoked thread's run was ended by the claim; look for the next.
          {:error, :forbidden} ->
            send(self(), :work)
            {:noreply, state}

          # The run is active but not claimable at this epoch: this host
          # already ran it and could not end it. The next host's claim does.
          {:error, :stale_run} ->
            {:stop, {:shutdown, :stale}, state}
        end
    end
  end

  def handle_info({:session, pid}, %{task: %Task{}} = state), do: {:noreply, %{state | session: pid}}

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    if store_unavailable?(result) do
      # The run stays running at this epoch, for the host that claims the
      # thread once the store is back to resume from what it stored.
      Logger.warning("thread #{state.id} could not reach its session store: #{inspect(result, limit: 5)}")
      {:stop, {:shutdown, :store_unavailable}, %{state | task: nil, session: nil}}
    else
      # A finish that fails was fenced: the run was ended meanwhile, as by an
      # archive, or this attempt lost it, as when the owner lost access. The
      # next look for work tells them apart: a run still active at this epoch
      # fails its claim, and the host exits so the next host's claim ends it.
      _ = Threads.finish(state.run, result)
      send(self(), :work)
      {:noreply, %{state | task: nil, session: nil, run: nil}}
    end
  end

  # The run's process crashed. Running it again would likely crash every
  # host in turn, so it ends interrupted; unknown tool effects stay unknown.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: %Task{ref: ref}} = state) do
    Logger.warning("thread #{state.id} run crashed: #{inspect(reason, limit: 5)}")
    _ = Threads.abandon(state.run)
    send(self(), :work)
    {:noreply, %{state | task: nil, session: nil, run: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # The session store could not load the session or journal the run's start,
  # as during an object storage outage. A fenced store means another host
  # holds the thread, which the finish's own fencing settles.
  defp store_unavailable?({:error, {failure, reason}})
       when failure in [:snapshot_load_failed, :journal_load_failed, :journal_failed], do: reason != :fenced

  defp store_unavailable?(_result), do: false

  defp execute(run, %{repository: nil} = thread, epoch, host), do: infer(run, thread, nil, epoch, host)

  defp execute(run, thread, epoch, host) do
    with {:ok, context} <- Workspace.prepare(thread, run) do
      result = infer(run, context.thread, context, epoch, host)
      Workspace.release(context)
      result
    end
  end

  defp infer(run, thread, context, epoch, host) do
    user = Accounts.get_user_by_id(thread.owner_id)
    deadline = System.monotonic_time(:millisecond) + @run_ms

    with {:ok, client_opts} <- Provider.client_opts(user, thread),
         {:ok, mcp_tools} <- mcp_tools(user, run) do
      # The run's process is the model calls' worker: they end with it.
      opts =
        ModelFence.wrap(client_opts, run, self()) ++
          [
            id: "#{thread.id}:#{run.id}",
            session_store: SessionStore.store("thread", thread.id, epoch),
            system_prompt: if(context, do: Agent.prompt(thread), else: Agent.system_prompt()),
            tools: tools(run, context) ++ mcp_tools,
            hooks: [{ToolLog, run: run, tools: @logged_tools}],
            load_project_instructions: false,
            max_tokens: 8192
          ] ++ sandbox(thread, context, deadline)

      with {:ok, pid} <- start_session(opts) do
        Process.link(pid)
        send(host, {:session, pid})

        try do
          # Under the message's request id: a run the previous host was
          # interrupted in resumes from its journal, with its stored prompt.
          Condukt.run(pid, prompt(pid, run, thread),
            max_turns: 12,
            request_id: run.message_id,
            timeout: left(deadline, @finish_ms)
          )
        after
          Process.unlink(pid)
          stop_session(pid, :normal)
          Threads.cancel_tool_calls(run, @logged_tools)
        end
      end
    end
  end

  # A session of this run can survive on another node only until its lease
  # lapsed, and its writes are fenced by then; this host holds the lease now,
  # so hand that one off.
  defp start_session(opts) do
    case Condukt.Sessions.start(Agent, opts) do
      {:error, {:already_started, pid}} ->
        stop_session(pid, {:shutdown, :drain})
        Condukt.Sessions.start(Agent, opts)

      other ->
        other
    end
  end

  defp stop_session(pid, reason) do
    GenServer.stop(pid, reason, 30_000)
  catch
    :exit, _ -> :ok
  end

  # A thread with stored history gets only its new message; one without, such
  # as a thread from before durable sessions, gets its transcript.
  defp prompt(pid, run, thread) do
    case Condukt.history(pid) do
      [] -> Agent.transcript(Threads.history(thread).messages)
      _ -> Repo.get!(Message, run.message_id).body
    end
  end

  defp left(deadline, margin), do: max(deadline - margin - System.monotonic_time(:millisecond), 1)

  defp sandbox(_thread, nil, _deadline), do: []

  defp sandbox(thread, context, deadline) do
    [
      cwd: "/workspace/repository",
      sandbox:
        {Tuist.Threads.Sandbox,
         sandbox_id: context.sandbox.id,
         account_id: thread.account_id,
         residency: context.residency,
         cwd: "/workspace/repository",
         commands_end_by: System.os_time(:millisecond) + left(deadline, @finish_ms + @answer_ms)}
    ]
  end

  defp mcp_tools(user, run) do
    case MCP.discover(user, run) do
      {:ok, tools} -> {:ok, tools}
      {:error, :stale_run} = error -> error
      # Profile integrations are optional. Their discovery failures must not
      # prevent the run from answering with its built-in tools.
      {:error, _} -> {:ok, []}
    end
  end

  defp tools(run, context) do
    naming =
      Condukt.tool(
        name: "set_thread_name",
        description: "Give this Thread a concise descriptive title.",
        parameters: schema(%{name: %{type: "string", maxLength: 120}}),
        call: fn args, _ -> Threads.rename(run, args["name"]) end,
        replay_safe: true
      )

    if context, do: [naming | @repository_tools], else: [naming]
  end

  defp schema(properties),
    do: %{type: "object", properties: properties, required: Map.keys(properties), additionalProperties: false}
end
