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
  alias Tuist.Threads.Repository
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
  # Workspace preparation that waited on a lock another process holds.
  @busy [:workspace_busy, :sandbox_account_busy]
  @busy_attempts 5
  @busy_retry_ms 2_000
  # Why no sandbox can be had now, as opposed to a broken checkout or a run
  # this host no longer owns.
  @unavailable [
    :no_capacity,
    :no_node,
    :not_connected,
    :node_disconnected,
    :timeout,
    :sandbox_concurrency_limit,
    :workspace_unavailable
  ]

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

  # Every run works in the thread's sandbox. A thread without a repository
  # has nothing there the conversation depends on yet, so when no sandbox can
  # be had (capacity, quota, no nodes in development, a sandbox that broke)
  # it still answers, without workspace tools, instead of failing. Contention
  # on the workspace or the account's quota row is brief: it is retried, and
  # never turns into a tool-less answer.
  defp execute(run, thread, epoch, host, attempts \\ @busy_attempts) do
    case Workspace.prepare(thread, run) do
      {:ok, context} ->
        result = infer(run, context.thread, context, epoch, host)
        Workspace.release(context)
        result

      {:error, reason} when reason in @busy and attempts > 1 ->
        Process.sleep(@busy_retry_ms)
        execute(run, thread, epoch, host, attempts - 1)

      {:error, reason} = error ->
        if is_nil(thread.repository) and unavailable?(reason) do
          Logger.warning("thread #{thread.id} runs without a workspace: #{inspect(reason)}")
          infer(run, thread, nil, epoch, host)
        else
          error
        end
    end
  end

  defp unavailable?({:invalid_state, _state}), do: true
  # CI took the node holding the paused sandbox.
  defp unavailable?({:host_busy, _}), do: true
  defp unavailable?(reason), do: reason in @unavailable

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
            system_prompt: Agent.prompt(thread, context),
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

  # A checked-out thread works in its checkout, as its history's relative
  # paths expect; one without a repository works in the workspace.
  defp sandbox(thread, context, deadline) do
    cwd = if context.thread.workspace_ready, do: "/workspace/repository", else: "/workspace"

    [
      cwd: cwd,
      sandbox:
        {Tuist.Threads.Sandbox,
         sandbox_id: context.sandbox.id,
         account_id: thread.account_id,
         residency: context.residency,
         cwd: cwd,
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

    workspace = if context, do: @repository_tools, else: []

    # Only a thread without a repository may ask for one. Its run is the
    # thread's, not the checkout's: these need no sandbox.
    requesting =
      if context && context.thread.repository do
        []
      else
        [
          Condukt.tool(
            name: "list_repositories",
            description:
              "List the account's GitHub repositories request_repository can ask for, with their default branches.",
            parameters: schema(%{}),
            call: fn _args, _ -> list_repositories(run) end,
            replay_safe: true
          ),
          Condukt.tool(
            name: "request_repository",
            description: """
            Check out a GitHub repository this request needs at /workspace/repository, on this thread's own branch.
            It becomes the thread's one repository, which Ship publishes to, so pick the one the person means; it
            is refused when the person cannot read it on GitHub. base_branch defaults to the repository's default
            branch.
            """,
            parameters: %{
              type: "object",
              properties: %{
                repository: %{type: "string", description: "owner/name, as list_repositories shows it"},
                base_branch: %{type: "string"}
              },
              required: ["repository"],
              additionalProperties: false
            },
            call: fn args, _ -> request_repository(run, context, args) end,
            replay_safe: true
          )
        ]
      end

    base = if Cards.available?(), do: [naming, card(run)], else: [naming]
    base ++ requesting ++ workspace
  end

  defp list_repositories(run) do
    thread = Repo.get!(Tuist.Threads.Thread, run.thread_id)

    with true <- Threads.owns_run?(run.id, run.attempt),
         {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
         {:ok, repositories} <- Repository.list(account) do
      shown = Enum.take(repositories, 500)
      lines = Enum.map_join(shown, "\n", &"#{&1.full_name} (default branch #{&1.default_branch})")

      cond do
        repositories == [] -> {:ok, "No repositories are available. The account's GitHub App installation has none."}
        length(repositories) > 500 -> {:ok, lines <> "\n(The first 500 of #{length(repositories)} repositories.)"}
        true -> {:ok, lines}
      end
    else
      false -> {:error, "This run no longer owns the thread."}
      _ -> {:error, "The repositories could not be listed. The account may not have the Tuist GitHub App installed."}
    end
  end

  defp request_repository(run, context, args) do
    case Threads.request_repository(run, Map.take(args, ["repository", "base_branch"])) do
      {:ok, {:attached, name, branch}} ->
        check_out(context, name, branch)

      {:error, :repository_attached} ->
        {:error, "This thread already works on another repository. Ask the person to start a new thread for this one."}

      {:error, reason} when reason in [:repository_access_denied, :github_identity_missing] ->
        {:error,
         "The person this thread belongs to cannot read that repository on GitHub " <>
           "(or has not linked a GitHub account), so it cannot be checked out."}

      {:error, :repository_too_large} ->
        {:error, "That repository is too large to check out in a thread."}

      {:error, reason} when reason in [:repository_not_authorized, :invalid_arguments, :repository_unavailable] ->
        {:error, "That repository or branch is not available to this account. list_repositories shows the repositories."}

      {:error, :stale_run} ->
        {:error, "This run no longer owns the thread."}

      {:error, _} ->
        {:error, "The repository could not be attached."}
    end
  end

  # Commands keep this run's working directory, /workspace: the checkout
  # becomes the working directory from the next run.
  defp check_out(nil, name, branch),
    do: {:ok, "#{name} (#{branch}) is the thread's repository. It is checked out at /workspace/repository next turn."}

  defp check_out(context, name, branch, attempts \\ @busy_attempts) do
    case Workspace.attach(context) do
      {:ok, thread} ->
        {:ok,
         "Checked out #{name} (#{branch}) at /workspace/repository on branch #{thread.branch}. " <>
           "Your working directory stays /workspace for this turn, so cd /workspace/repository in commands."}

      {:error, :stale_run} ->
        {:error, "This run no longer owns the thread."}

      # Another tool of this turn, such as an MCP call, holds the workspace.
      {:error, :workspace_busy} when attempts > 1 ->
        Process.sleep(@busy_retry_ms)
        check_out(context, name, branch, attempts - 1)

      {:error, :repository_too_large} ->
        {:error, "#{name} is too large to check out in a thread, so it is no longer the thread's repository."}

      {:error, _} ->
        {:error,
         "#{name} is the thread's repository, but checking it out did not finish. " <>
           "It is checked out again at the start of the next turn."}
    end
  end

  # Tuist Guild runs the card natively; other clients show its summary.
  defp card(run) do
    Condukt.tool(
      name: "show_ui",
      description: """
      Show the person a small native card in the conversation, a TSX module composed from Guild's card kit.
      Use it sparingly: only when something visual explains your answer better than text, such as a comparison,
      a chart, a timeline or a few numbers side by side. Most answers need no card; never use one for prose, code or
      plain lists, and show at most one per answer.

      The card fills a fixed frame: `compact` is 120, `medium` 240 and `tall` 400 points high, and it is 320 to 600
      points wide; make the content fit the narrowest width. The app draws the card's surface, pads it and styles
      every component in its own theme, so a card only composes the kit: import everything from "./guild", which
      is the only module a card may import, and end with `mount(App)`. The kit has no `class` or `style` props.

      - `VStack` and `HStack` (props `gap`: "tight" | "normal" | "loose"; `grow` takes the space left; HStack also
        `align`: "start" | "center" | "end"), `Spacer` and `Divider` lay out.
      - `Title`, `Body` and `Caption` take text.
      - `Stat` (`label`, `value`, optional `detail`) shows one key number; put two or three in an HStack.
      - `Meter` (`label`, `value` from 0 to 1, optional `trailing` text) is a labelled bar, for comparisons.
      - `Row` (`title`, optional `detail` and `trailing`) is a list row.
      - `Badge` (`tone`: "neutral" | "accent" | "danger") is a short status label.
      - `Action` (`reply`, optional `prominent`, its label as children) suggests the person's next message: pressing
        it puts `reply` in the composer for them to send. Use one prominent action at most, at the bottom.
      - `signal` holds state that changes while the card is shown.

      For example:

      ```tsx
      import { Action, HStack, Meter, mount, Spacer, Stat, Title, VStack } from "./guild";

      function App() {
        return (
          <VStack grow>
            <Title>Build times this week</Title>
            <HStack gap="loose">
              <Stat label="Median" value="412 s" detail="+12% vs last week" />
              <Stat label="Cache hits" value="31%" />
            </HStack>
            <Meter label="TuistKit" value={0.31} trailing="412 s" />
            <Spacer />
            <Action prominent reply="Why does TuistKit miss the cache?">Ask why</Action>
          </VStack>
        );
      }

      mount(App);
      ```

      The card can't fetch data or open links: put its data in the module. The server builds the card and opens it
      headless before showing it. When it doesn't compile, throws or doesn't fit its frame, the call fails with what
      to fix. `summary` says what the card shows in one or two sentences, for clients that can't run it.
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
