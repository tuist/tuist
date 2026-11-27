defmodule LuftServer.Threads.Host do
  @moduledoc """
  Lease-hosted durable inference runs. Session identity is `<thread>:<run>`;
  the encrypted journal belongs to the thread and is fenced by the lease epoch.
  A drained run resumes under its original message request ID. Crashed workers
  are abandoned, while temporary journal outages back off without finishing.

  Workspace and personal-tool operations use explicit delegated capability
  boundaries. Discovery failures fail the run instead of silently dropping
  tools. Native cards are checked locally; hosted runs can attach their one
  repository through the fenced Threads and Workspace boundaries.
  """
  @behaviour Condukt.Notifier
  @behaviour LuftServer.Agents.Kind

  use GenServer, restart: :temporary

  import Ecto.Query, only: [from: 2]

  alias Condukt.Tools.Bash
  alias Condukt.Tools.Edit
  alias Condukt.Tools.Ls
  alias Condukt.Tools.Read
  alias Condukt.Tools.Write
  alias LuftServer.Agents.Kind
  alias LuftServer.Agents.Lease
  alias LuftServer.Agents.SessionStore
  alias LuftServer.Repo
  alias LuftServer.Threads
  alias LuftServer.Threads.Agent
  alias LuftServer.Threads.AskUser
  alias LuftServer.Threads.Attachments
  alias LuftServer.Threads.Capabilities
  alias LuftServer.Threads.Cards
  alias LuftServer.Threads.Clients
  alias LuftServer.Threads.MCP
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.ModelFence
  alias LuftServer.Threads.Provider
  alias LuftServer.Threads.Runners
  alias LuftServer.Threads.RunnerSandbox
  alias LuftServer.Threads.Sandbox
  alias LuftServer.Threads.Thread
  alias LuftServer.Threads.ToolLog
  alias LuftServer.Threads.TuistTools
  alias LuftServer.Threads.Workspace
  alias LuftServer.Workspaces.Authoring
  alias LuftServer.Workspaces.Records

  require Logger

  @run_ms 3_600_000
  @heartbeat_ms 15_000
  @logged_tools ~w(Read Glob Grep Ls Write Edit Bash)
  @repository_tools [
    Read,
    Condukt.Tools.Glob,
    Condukt.Tools.Grep,
    Ls,
    Write,
    Edit,
    {Bash, replay_safe: true}
  ]

  @impl Kind
  def start(id, epoch),
    do: DynamicSupervisor.start_child(LuftServer.Agents.Hosts, {__MODULE__, {id, epoch}})

  @impl Kind
  def stop_if_idle(pid, reply_to, token),
    do: GenServer.cast(pid, {:stop_if_idle, reply_to, token})

  @impl Kind
  def drain(pid), do: GenServer.cast(pid, :drain)
  def start_link({id, epoch}), do: GenServer.start_link(__MODULE__, {id, epoch})

  @impl Condukt.Notifier
  def publish(_id, {:waiting, %{tool_calls: calls}}, opts) do
    if Enum.any?(calls, &(&1.tool == "ask_user")),
      do: send(opts[:host], {:question_waiting, opts[:run_id]})

    :ok
  end

  def publish(_id, _event, _opts), do: :ok

  @impl true
  def init({id, epoch}) do
    Phoenix.PubSub.subscribe(LuftServer.PubSub, Lease.topic(id))
    send(self(), :work)
    Process.send_after(self(), :heartbeat, @heartbeat_ms)
    {:ok, %{id: id, epoch: epoch, task: nil, run: nil, session: nil, workspace: nil}}
  end

  @impl true
  def handle_cast({:stop_if_idle, reply_to, token}, %{task: nil} = state) do
    case next_run(state) do
      {:ok, nil} ->
        send(reply_to, {Kind, :idle, self(), token})
        {:stop, :normal, state}

      {:ok, _} ->
        send(self(), :work)
        {:noreply, state}

      :error ->
        {:stop, {:shutdown, :unavailable}, state}
    end
  end

  def handle_cast({:stop_if_idle, _reply_to, _token}, state), do: {:noreply, state}

  def handle_cast(:drain, state) do
    stop_work(state)
    {:stop, {:shutdown, :drain}, %{state | task: nil, session: nil}}
  end

  @impl true
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

            task =
              Task.Supervisor.async_nolink(LuftServer.Threads.Tasks, fn ->
                execute(run, thread, epoch, host)
              end)

            {:noreply, %{state | task: task, run: run, workspace: nil}}

          {:error, reason} when reason in [:forbidden, :expired] ->
            send(self(), :work)
            {:noreply, state}

          {:error, :stale_run} ->
            {:stop, {:shutdown, :stale}, state}

          {:error, :tuist_unavailable} ->
            {:stop, {:shutdown, :unavailable}, state}
        end
    end
  end

  def handle_info({:session, pid}, %{task: %Task{}} = state),
    do: {:noreply, %{state | session: pid}}

  def handle_info({:workspace, context}, %{task: %Task{}} = state),
    do: {:noreply, %{state | workspace: context}}

  def handle_info({:question_waiting, id}, %{run: %{id: id}} = state) do
    stop_work(state)
    if state.workspace, do: Workspace.release(state.workspace)
    {:stop, :normal, %{state | task: nil, session: nil, run: nil}}
  end

  def handle_info(:heartbeat, state) do
    Process.send_after(self(), :heartbeat, @heartbeat_ms)
    if state.run, do: keep_alive(state.run)
    {:noreply, state}
  end

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    if store_unavailable?(result) do
      Logger.warning("thread #{state.id} session store unavailable")
      {:stop, {:shutdown, :unavailable}, %{state | task: nil, session: nil}}
    else
      log_failure(state.id, result)
      _ = Threads.finish(state.run, result)
      send(self(), :work)
      {:noreply, %{state | task: nil, session: nil, run: nil}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state) do
    Logger.warning("thread #{state.id} run worker crashed")
    _ = Threads.abandon(state.run)
    send(self(), :work)
    {:noreply, %{state | task: nil, session: nil, run: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp next_run(state) do
    {:ok, Threads.next_run(state.id)}
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> :error
  end

  defp keep_alive(run) do
    Threads.keep_alive(run)
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> :ok
  end

  defp stop_work(state) do
    if state.session, do: stop_session(state.session, {:shutdown, :drain})
    if state.task, do: Task.shutdown(state.task, :brutal_kill)
  end

  defp store_unavailable?({:error, {failure, reason}})
       when failure in [:snapshot_load_failed, :journal_load_failed, :journal_failed] do
    reason not in [:fenced, :undecodable, :missing, :invalid_snapshot, :invalid_journal] and
      not match?({:unsupported_snapshot_version, _}, reason)
  end

  defp store_unavailable?(_), do: false

  # Only atom reasons: other error terms can carry provider responses.
  defp log_failure(_id, {:ok, _}), do: :ok

  defp log_failure(id, {:error, reason}) when is_atom(reason),
    do: Logger.warning("thread #{id} run failed: #{reason}")

  defp log_failure(id, _), do: Logger.warning("thread #{id} run failed")

  defp execute(run, thread, epoch, host) do
    message = Repo.get!(Message, run.message_id)

    with {:ok, _owner, owner_scope} <- Provider.owner(thread),
         {:ok, _author, author_scope} <- Provider.author(thread, message),
         {:ok, client_opts} <- Provider.client_opts(thread),
         {:ok, builtin} <- TuistTools.tools(thread, message, run),
         {:ok, context} <- prepare(thread, run) do
      if is_map(context), do: send(host, {:workspace, context})
      current = if is_map(context), do: context.thread, else: thread
      current = Threads.history(current, owner_scope)

      try do
        infer(
          run,
          current,
          message,
          %{
            author_id: author_scope.user_id,
            client_opts: client_opts,
            builtin: builtin,
            context: context
          },
          epoch,
          host
        )
      after
        if is_map(context), do: Workspace.release(context)
      end
    end
  end

  defp prepare(thread, run, attempts \\ 5)

  defp prepare(%{runner_id: id} = thread, _run, _attempts) when is_binary(id) do
    with {:ok, runner} <- Runners.for_thread(thread), do: {:ok, {:runner, runner}}
  end

  defp prepare(thread, run, attempts) do
    case Workspace.prepare(thread, run) do
      {:error, reason} when reason in [:workspace_busy, :sandbox_account_busy] and attempts > 1 ->
        Process.sleep(2_000)
        prepare(thread, run, attempts - 1)

      result ->
        result
    end
  end

  defp infer(run, thread, message, runtime, epoch, host) do
    deadline = System.monotonic_time(:millisecond) + @run_ms
    sandbox_opts = sandbox(thread, runtime.context, run, deadline)

    reserved =
      tools(run) ++
        repository_tools(run, runtime.context) ++
        workspace_tools(run, runtime.context) ++
        client_tools(run, thread, message, runtime.author_id)

    with {:ok, personal_tools, skipped} <-
           MCP.discover(thread, message, run, runtime.builtin, length(reserved)),
         :ok <- notify_skipped(run, skipped) do
      opts =
        ModelFence.wrap(runtime.client_opts, run, self()) ++
          [
            id: "#{thread.id}:#{run.id}",
            session_store: SessionStore.store("thread", thread.id, epoch),
            notifier: {__MODULE__, host: host, run_id: run.id},
            system_prompt: Agent.prompt(thread, runtime.context),
            tools: reserved ++ personal_tools,
            hooks: [{ToolLog, run: run, tools: @logged_tools}],
            compactor: Attachments,
            background_compaction: false,
            load_project_instructions: false,
            max_tokens: 8192
          ] ++ sandbox_opts

      run_session(run, thread, message, opts, deadline, host)
    end
  end

  defp notify_skipped(_run, []), do: :ok

  defp notify_skipped(run, names) do
    quoted = Enum.map_join(names, ", ", &"“#{&1}”")
    {subject, pronoun} = if length(names) == 1, do: {"server", "it"}, else: {"servers", "them"}

    with {:ok, :ok} <-
           Threads.record_notice(
             run,
             "This run continues without the MCP #{subject} #{quoted}, which did not respond. Reconnect or remove #{pronoun} under MCP servers in your Tuist AI settings."
           ),
         do: :ok
  end

  defp run_session(run, thread, message, opts, deadline, host) do
    with {:ok, files} <- Attachments.materialize(thread.messages, opts[:sandbox]),
         {:ok, pid} <- start_session(opts) do
      Process.link(pid)
      send(host, {:session, pid})

      try do
        prompt =
          case Condukt.history(pid) do
            [] -> Agent.transcript(thread.messages)
            _ -> message.body
          end

        Condukt.run(pid, prompt <> files,
          images: Attachments.images([message]),
          max_turns: 12,
          request_id: run.message_id,
          timeout: max(deadline - 30_000 - System.monotonic_time(:millisecond), 1)
        )
      after
        Process.unlink(pid)
        stop_session(pid, :normal)
        Threads.cancel_tool_calls(run, @logged_tools)
      end
    end
  end

  defp sandbox(_thread, {:runner, runner}, run, _deadline) do
    cwd = runner.capabilities["new_project_folder"] || "~"
    [cwd: cwd, sandbox: {RunnerSandbox, runner_id: runner.id, run: run, cwd: cwd}]
  end

  defp sandbox(thread, context, run, deadline) do
    cwd = if thread.workspace_ready, do: "/workspace/repository", else: "/workspace"

    [
      cwd: cwd,
      sandbox:
        {Sandbox,
         sandbox_id: context.sandbox.id,
         account_id: thread.account_id,
         owner: context.sandbox.owner,
         residency: context.residency,
         cwd: cwd,
         commands_end_by:
           System.os_time(:millisecond) +
             max(deadline - 90_000 - System.monotonic_time(:millisecond), 1),
         run: %{id: run.id, thread_id: thread.id, attempt: run.attempt}}
    ]
  end

  defp workspace_tools(run, {:runner, runner}) do
    files = [Read, Ls, Write, Edit]
    shell = if runner.capabilities["terminal"], do: [Bash], else: []
    display = if runner.capabilities["display"], do: display_tools(run, runner), else: []
    files ++ shell ++ display
  end

  defp workspace_tools(_run, _context), do: @repository_tools

  defp display_tools(run, runner) do
    point = %{x: %{type: "number"}, y: %{type: "number"}}

    definitions = [
      {"screenshot", "Take a screenshot of the runner's main display.", %{}},
      {"click", "Click a point on the runner's display, in points from its top left.",
       Map.merge(point, %{
         button: %{type: "string", enum: ["left", "right"]},
         count: %{type: "integer", minimum: 1, maximum: 3}
       })},
      {"mouse_move", "Move the pointer to a point on the runner's display.", point},
      {"scroll", "Scroll the runner's display in pixels; negative dy scrolls down.",
       %{dx: %{type: "integer"}, dy: %{type: "integer"}}},
      {"type_text", "Type text on the runner's display.",
       %{text: %{type: "string", maxLength: 4000}}},
      {"key", "Press a named key with optional command, shift, option or control modifiers.",
       %{key: %{type: "string"}, modifiers: %{type: "array", items: %{type: "string"}}}}
    ]

    Enum.map(definitions, fn {op, description, properties} ->
      Condukt.tool(
        name: "display_" <> op,
        description: description,
        parameters: %{type: "object", properties: properties, additionalProperties: false},
        call: fn args, _ ->
          keys = Enum.map(Map.keys(properties), &Atom.to_string/1)

          case RunnerSandbox.display(runner.id, run, op, Map.take(args, keys)) do
            {:ok, %{"mime_type" => media_type, "data" => data}} ->
              {:ok, %{type: :image, media_type: media_type, data: data}}

            {:ok, _} ->
              {:ok, "Done."}

            {:error, reason} ->
              {:error, to_string(reason)}
          end
        end
      )
    end)
  end

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

  defp client_tools(run, thread, message, author_id) do
    first =
      Repo.aggregate(
        from(m in Message, where: m.thread_id == ^thread.id and m.kind == "human"),
        :count
      ) <= 1

    wait = Application.get_env(:luft_server, __MODULE__, [])[:client_wait_ms] || 2_000

    offered =
      if first,
        do: Clients.await_tools(thread.id, author_id, wait),
        else: Clients.tools(thread.id, author_id)

    Enum.map(offered, fn tool ->
      name = Clients.prefix() <> tool.name

      Condukt.tool(
        name: name,
        description: "Runs in the original author's app. " <> tool.description,
        parameters: tool.parameters,
        call: fn args, _ ->
          with true <- Threads.owns_run?(run.id, run.attempt),
               {:ok, _session, _scope} <- Provider.author(thread, message) do
            result = Clients.call(thread.id, author_id, tool.name, args)
            _ = Threads.record_client_tool(run, name, result)
            result
          else
            _ -> {:error, "This run or the original author's delegation is no longer available."}
          end
        end
      )
    end)
  end

  defp tools(run) do
    base = [
      Condukt.tool(
        name: "workspace_queries",
        description:
          "Discover permitted business collections for the triggering author. Returns module, query, model and operation (list or get). Use query_workspace to locate a record, then show_record to present it with reader-specific permissions.",
        parameters: %{type: "object", properties: %{}, additionalProperties: false},
        call: fn args, _ -> Records.discover(run, args) end,
        replay_safe: true
      ),
      Condukt.tool(
        name: "query_workspace",
        description:
          "Run a query from workspace_queries under fresh author permissions. Get input is {id}; list input is {} or, for reviewed behavior collections, {search}. Behavior collections return opaque reference(s), not record fields; show_record opens native detail for each reader. Legacy workspaces return rows. Does not write.",
        parameters: %{
          type: "object",
          properties: %{
            module: %{type: "string"},
            query: %{type: "string"},
            input: %{
              type: "object",
              properties: %{
                id: %{type: "string", format: "uuid"},
                search: %{type: "string", maxLength: 200}
              },
              additionalProperties: false
            }
          },
          required: ["module", "query", "input"],
          additionalProperties: false
        },
        call: fn args, _ -> Records.query(run, args) end,
        replay_safe: true
      ),
      Condukt.tool(
        name: "show_record",
        description:
          "Show a business record reference, not a data snapshot. Checks the triggering author's fresh delegation and explicit workspace read grant before appending. Each reader opens current data under their own permissions. Use an authorized query to find the model and UUID; do not guess IDs.",
        parameters: %{
          type: "object",
          properties: %{model: %{type: "string"}, id: %{type: "string", format: "uuid"}},
          required: ["model", "id"],
          additionalProperties: false
        },
        call: fn args, _ -> Threads.show_record(run, args) end,
        replay_safe: true
      ),
      Condukt.tool(
        name: "set_thread_name",
        description: "Give this thread a concise descriptive title.",
        parameters: %{
          type: "object",
          properties: %{name: %{type: "string", maxLength: 120}},
          required: ["name"],
          additionalProperties: false
        },
        call: fn args, _ -> Threads.rename(run, args["name"]) end,
        replay_safe: true
      ),
      Condukt.tool(
        name: "update_progress",
        description: "Update the visible plan for this run. Mark only finished steps completed.",
        parameters: %{
          type: "object",
          properties: %{
            steps: %{
              type: "array",
              minItems: 1,
              maxItems: 20,
              items: %{
                type: "object",
                properties: %{
                  title: %{type: "string", maxLength: 120},
                  status: %{type: "string", enum: ["pending", "in_progress", "completed"]}
                },
                required: ["title", "status"],
                additionalProperties: false
              }
            }
          },
          required: ["steps"],
          additionalProperties: false
        },
        call: fn args, _ -> Threads.update_progress(run, args["steps"]) end,
        replay_safe: true
      ),
      {AskUser, run: run}
    ]

    base = base ++ Authoring.tools(run)
    if Cards.available?(), do: base ++ [card(run)], else: base
  end

  defp card(run) do
    Condukt.tool(
      name: "show_ui",
      description: """
      Show one small native card when a chart, comparison, timeline or a few numbers explain the answer better than text. Most answers need no card; use text for prose, code and plain lists. The card is a TSX module that imports only "./luft" and ends with mount(App).
      Frames are compact=120, medium=240, tall=400 points high, at widths 320–600; content must fit the narrowest width. The kit supplies VStack/HStack (gap: tight|normal|loose, grow; HStack align: start|center|end), Spacer, Divider, Title, Body, Caption, Stat (label,value,detail), Meter (label,value 0–1,trailing), Row (title,detail,trailing), Badge (tone: neutral|accent|danger), Action (reply,prominent) and signal. There are no class or style props. Put long content in Scroll. An Action only drafts the person's next message; it grants no permission to act. The card cannot fetch data or open links. Embed its data and give a one- or two-sentence summary for clients without native cards. Compilation and headless layout checks return repairable errors before presentation.
      """,
      parameters: %{
        type: "object",
        properties: %{
          tsx: %{type: "string"},
          size: %{type: "string", enum: Cards.sizes()},
          summary: %{type: "string", maxLength: 2000}
        },
        required: ["tsx", "size", "summary"],
        additionalProperties: false
      },
      call: fn args, _ ->
        summary = args["summary"]

        with true <- Threads.owns_run?(run.id, run.attempt),
             true <-
               is_binary(summary) and String.trim(summary) != "" and
                 String.length(summary) <= 2000,
             {:ok, source} <- Cards.build(args["tsx"], args["size"]) do
          Threads.show_card(run, String.trim(summary), args["size"], source)
        else
          false ->
            {:error, "Give a summary under 2000 characters while this run owns the thread."}

          error ->
            error
        end
      end,
      replay_safe: true
    )
  end

  defp repository_tools(_run, {:runner, _}), do: []

  defp repository_tools(_run, %{thread: %{repository: repository}}) when not is_nil(repository),
    do: []

  defp repository_tools(run, context) do
    [
      Condukt.tool(
        name: "list_repositories",
        description:
          "List the account's GitHub repositories and default branches that request_repository may attach.",
        parameters: %{type: "object", properties: %{}, additionalProperties: false},
        call: fn _, _ -> list_repositories(run) end,
        replay_safe: true
      ),
      Condukt.tool(
        name: "request_repository",
        description:
          "Check out the GitHub repository this request needs at /workspace/repository on this thread's branch. It becomes the thread's one repository for Ship; choose the one the person means. The owner must be able to read it. base_branch defaults to its default branch.",
        parameters: %{
          type: "object",
          properties: %{
            repository: %{type: "string", description: "owner/name from list_repositories"},
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

  defp list_repositories(run) do
    thread = Repo.get!(Thread, run.thread_id)

    with true <- Threads.owns_run?(run.id, run.attempt),
         {:ok, owner} <- Capabilities.owner(thread),
         {:ok, repositories} when is_list(repositories) <-
           Capabilities.request(owner, "repositories") do
      lines =
        repositories
        |> Enum.take(500)
        |> Enum.map_join("\n", &"#{&1["full_name"]} (default branch #{&1["default_branch"]})")

      cond do
        repositories == [] ->
          {:ok, "No repositories are available to the account's GitHub App installation."}

        length(repositories) > 500 ->
          {:ok, lines <> "\n(The first 500 of #{length(repositories)} repositories.)"}

        true ->
          {:ok, lines}
      end
    else
      _ ->
        {:error,
         "The repositories could not be listed. Check the run's delegation and the account's GitHub App installation."}
    end
  end

  defp request_repository(run, context, args) do
    case Threads.request_repository(run, Map.take(args, ["repository", "base_branch"])) do
      {:ok, {:attached, name, branch}} ->
        check_out(context, name, branch)

      {:error, :repository_attached} ->
        {:error,
         "This thread already works on another repository. Start a new thread for this one."}

      {:error, reason} when reason in [:repository_access_denied, :github_identity_missing] ->
        {:error,
         "The thread's owner cannot read this repository on GitHub, or has not linked a GitHub identity."}

      {:error, :repository_too_large} ->
        {:error, "This repository is too large to check out."}

      {:error, :stale_run} ->
        {:error, "This run no longer owns the thread."}

      {:error, _} ->
        {:error,
         "The repository or branch could not be attached. Use list_repositories to check availability."}
    end
  end

  defp check_out(context, name, branch, attempts \\ 5) do
    case Workspace.attach(context) do
      {:ok, thread} ->
        {:ok,
         "Checked out #{name} (#{branch}) at /workspace/repository on #{thread.branch}. This turn's cwd stays /workspace; use cd /workspace/repository in commands."}

      {:error, :workspace_busy} when attempts > 1 ->
        Process.sleep(2_000)
        check_out(context, name, branch, attempts - 1)

      {:error, :stale_run} ->
        {:error, "This run no longer owns the thread."}

      {:error, _} ->
        {:error,
         "#{name} is bound to this thread, but checkout did not finish. The next run retries checkout."}
    end
  end
end
