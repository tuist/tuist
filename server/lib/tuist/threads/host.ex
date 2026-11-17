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
  alias Tuist.Threads.Cards
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
  # Under the previous release's recovery sweep's 60 seconds, which still runs
  # on its pods during a rolling deploy (`Tuist.Threads.keep_alive/1`).
  @heartbeat_ms 15_000

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
    Process.send_after(self(), :heartbeat, @heartbeat_ms)
    {:ok, %{id: id, epoch: epoch, task: nil, run: nil, session: nil}}
  end

  @impl GenServer
  def handle_cast({:stop_if_idle, reply_to, token}, state) do
    # One step of this process: work that arrives later finds it gone, and
    # its want keeps the thread wanted (`Tuist.Agents.Lease.release/3`).
    if state.task do
      {:noreply, state}
    else
      case next_run(state) do
        {:ok, nil} ->
          send(reply_to, {Kind, :idle, self(), token})
          {:stop, :normal, state}

        # Work this host was not woken for, as when the wake was lost.
        {:ok, _run_id} ->
          send(self(), :work)
          {:noreply, state}

        :error ->
          {:stop, {:shutdown, :unavailable}, state}
      end
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
    case next_run(state) do
      {:ok, nil} ->
        {:noreply, state}

      :error ->
        {:stop, {:shutdown, :unavailable}, state}

      {:ok, run_id} ->
        case Threads.claim(run_id, state.epoch) do
          {:ok, {run, thread}} ->
            {epoch, host} = {state.epoch, self()}
            task = Task.Supervisor.async_nolink(Tuist.Threads.Tasks, fn -> execute(run, thread, epoch, host) end)

            {:noreply, %{state | task: task, run: run}}

          # A revoked thread's run, or one past its age, was ended by the
          # claim; look for the next.
          {:error, reason} when reason in [:forbidden, :expired] ->
            send(self(), :work)
            {:noreply, state}

          # The run is active but not claimable at this epoch: this host lost
          # its lease, or already ran it and could not end it. The next host's
          # claim does.
          {:error, :stale_run} ->
            {:stop, {:shutdown, :stale}, state}
        end
    end
  end

  def handle_info({:session, pid}, %{task: %Task{}} = state), do: {:noreply, %{state | session: pid}}

  def handle_info(:heartbeat, state) do
    Process.send_after(self(), :heartbeat, @heartbeat_ms)
    if state.run, do: keep_alive(state)
    {:noreply, state}
  end

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    if store_failure(result) == :unavailable do
      # The run stays running at this epoch, for the host that claims the
      # thread once the store is back to resume from what it stored.
      Logger.warning("thread #{state.id} could not reach its session store: #{inspect(result, limit: 5)}")
      {:stop, {:shutdown, :unavailable}, %{state | task: nil, session: nil}}
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

  # A database that fails while this host has no run hands the thread on, as
  # an unreachable store does, so a later host retries after a backoff.
  defp next_run(state) do
    {:ok, Threads.next_run(state.id)}
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("thread #{state.id} could not look for work: #{Exception.message(error)}")
      :error
  end

  # A heartbeat that fails while the run's task works must not crash this
  # process and leave the task running unowned; the next one tries again.
  defp keep_alive(state) do
    Threads.keep_alive(state.run)
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning("thread #{state.id} heartbeat failed: #{Exception.message(error)}")
  end

  # Whether the session store failed to load the session or journal the
  # run's start. What it stored but cannot be read, such as an object that
  # does not decrypt or a segment that is gone, stays that way, so the run
  # ends; anything else, as during an object storage outage, is retried by a
  # later host. A fenced store means another host holds the thread, which the
  # finish's own fencing settles.
  defp store_failure({:error, {failure, reason}})
       when failure in [:snapshot_load_failed, :journal_load_failed, :journal_failed] do
    cond do
      reason == :fenced -> nil
      unreadable?(reason) -> :unreadable
      true -> :unavailable
    end
  end

  defp store_failure(_result), do: nil

  defp unreadable?(reason) when reason in [:undecodable, :missing, :invalid_snapshot, :invalid_journal], do: true
  defp unreadable?({:unsupported_snapshot_version, _version}), do: true
  defp unreadable?(_reason), do: false

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

    tools = if Cards.available?(), do: [naming, card(run)], else: [naming]
    if context, do: tools ++ @repository_tools, else: tools
  end

  # Tuist Guild runs the card natively; other clients show its summary.
  defp card(run) do
    Condukt.tool(
      name: "show_ui",
      description: """
      Show the person a small native card in the conversation, written as one TSX module for NSH (https://nsh.dev).
      Use it sparingly: only when something visual explains your answer better than text, such as a comparison,
      a chart, a timeline or a few numbers side by side. Most answers need no card; never use one for prose, code or
      plain lists, and show at most one per answer.

      The card fills a fixed frame: `compact` is 120, `medium` 240 and `tall` 400 points high, and it is 320 to 600
      points wide. Give its root view `flex-1` and make the content fit the narrowest width. Import only from `nsh`
      (View, Text, Scroll, mount, host) and `nsh/base`, style with Tailwind classes on the theme's tokens
      (bg-card, text-card-foreground, text-muted-foreground, bg-muted, bg-primary, text-primary-foreground,
      border-border) so it follows light and dark mode, and end with `mount(App)`. The card can't fetch data or open
      links: put its data in the module. A pressable view may suggest the person's next message, which they send themselves, with
      `if (host.available()) host.call("reply", text)`.

      The server builds the card and opens it headless before showing it. When it doesn't compile, throws or doesn't
      fit its frame, the call fails with what to fix. `summary` says what the card shows in one or two sentences, for
      clients that can't run it.
      """,
      parameters:
        schema(%{
          tsx: %{type: "string", description: "The card's TSX module."},
          size: %{type: "string", enum: Cards.sizes()},
          summary: %{type: "string", maxLength: 2000}
        }),
      call: fn args, _ ->
        summary = args["summary"]

        with :ok <-
               if(is_binary(summary) and String.trim(summary) != "", do: :ok, else: {:error, "Give the card a summary."}),
             {:ok, source} <- Cards.build(args["tsx"], args["size"]) do
          Threads.show_card(run, String.trim(summary), args["size"], source)
        end
      end,
      replay_safe: true
    )
  end

  defp schema(properties),
    do: %{type: "object", properties: properties, required: Map.keys(properties), additionalProperties: false}
end
