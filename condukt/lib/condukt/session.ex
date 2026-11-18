defmodule Condukt.Session do
  @moduledoc """
  GenServer that manages an agent session.

  The session maintains:
  - Conversation history (messages)
  - Current model configuration
  - Available tools
  - Streaming state

  ## The Agent Loop

  When a prompt is received:

  1. Add user message to history
  2. Call LLM with system prompt, messages, and tools
  3. If LLM returns tool calls:
     - Execute each tool
     - Add tool results to history
     - Go to step 2
  4. If LLM returns text only, return response
  """

  use GenServer

  alias Condukt.AgentRuntimes.Native

  alias Condukt.{
    Context,
    Hooks,
    Message,
    Park,
    Retry,
    Sandbox,
    Secrets,
    SessionID,
    SessionStore,
    Signal,
    Telemetry,
    Tool,
    TraceContext
  }

  alias Condukt.MCP
  alias Condukt.Notifier
  alias Condukt.Session.Compaction
  alias Condukt.Session.Durable
  alias Condukt.Session.Parking
  alias Condukt.Session.Translate
  alias Condukt.Session.Turn
  alias Condukt.Session.View
  alias Condukt.Session.Viewer
  alias Condukt.Sessions.Inbox
  alias Condukt.SessionStore.Snapshot
  alias Condukt.Tool.Inline
  alias Condukt.Tools.Subagent

  require Logger

  @default_timeout 300_000
  @default_max_turns 50
  # Calls that run at once when hooks may hold them waiting on a person.
  @max_hooked_tool_concurrency 64
  # How long a stopped worker that traps exits gets before it is killed. A
  # longer wait would make `abort/1`, which waits for it, time out.
  @worker_shutdown 100
  # `Process.send_after/3` takes at most 2^32 - 1 ms; a later deadline re-arms.
  @max_timer 4_294_967_295

  defstruct [
    :id,
    :actor,
    :created_at,
    :pid,
    :agent_module,
    :runtime,
    :llm,
    :configured_system_prompt,
    :system_prompt,
    :tools,
    :hooks,
    :subagents,
    :subagent_supervisor,
    :turn_supervisor,
    :cwd,
    :sandbox,
    :secrets,
    :mcp_registry,
    :notifier,
    :session_store,
    :session_store_opts,
    :redactor,
    :project_context,
    :user_state,
    :viewer,
    :inbox,
    compaction: %Compaction{},
    durable: %Durable{},
    messages: [],
    turn: %Condukt.Session.Turn{},
    assigns: %{}
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc false
  def start_link(agent_module, opts) do
    start_session(:link, agent_module, opts)
  end

  @doc false
  def start(agent_module, opts) do
    start_session(:nolink, agent_module, opts)
  end

  @doc false
  def with_transient(agent_module, opts, fun) when is_function(fun, 1) do
    case start(agent_module, opts) do
      {:ok, pid} ->
        try do
          fun.(pid)
        after
          if Process.alive?(pid), do: GenServer.stop(pid)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_session(link_mode, agent_module, opts) do
    config = Keyword.get(opts, :config, [])
    explicit_keys = opts |> Keyword.keys() |> MapSet.new()
    opts = Keyword.delete(opts, :config)
    {gen_opts, agent_opts} = Keyword.split(opts, [:name])

    agent_opts =
      agent_opts
      |> Keyword.put_new(:agent_module, agent_module)
      |> Keyword.put(:explicit_keys, explicit_keys)
      |> put_configured_opt(config, :api_key)
      |> put_configured_opt(config, :base_url)
      |> put_configured_opt(config, :llm_request_options, fn -> [] end)
      |> put_configured_opt(config, :runtime, fn -> agent_runtime(agent_module) end)
      |> put_configured_opt(config, :model, fn -> agent_module.model() end)
      |> put_configured_opt(config, :thinking_level, fn -> agent_module.thinking_level() end)
      |> put_configured_opt(config, :max_tokens, fn -> agent_max_tokens(agent_module) end)
      |> put_configured_opt(config, :system_prompt, fn -> agent_module.system_prompt() end)
      |> put_configured_opt(config, :load_project_instructions, fn -> true end)
      |> Keyword.put_new(:tools, agent_module.tools())
      |> Keyword.put_new_lazy(:hooks, fn -> agent_hooks(agent_module) end)
      |> Keyword.put_new(:subagents, agent_subagents(agent_module))
      |> Keyword.put_new(:mcp_servers, agent_mcp_servers(agent_module))
      |> put_configured_opt(config, :cwd, &File.cwd!/0)
      |> put_configured_opt(config, :sandbox, fn -> agent_sandbox(agent_module) end)
      |> put_configured_opt(config, :secrets, fn -> agent_secrets(agent_module) end)
      |> put_configured_opt(config, :session_store)
      |> put_configured_opt(config, :session_store_key)
      |> put_configured_opt(config, :session_store_opts, fn -> [] end)
      |> put_configured_opt(config, :restart_limit, &Durable.default_restart_limit/0)
      |> put_configured_opt(config, :compactor)
      |> put_configured_opt(config, :background_compaction)
      |> put_configured_opt(config, :redactor)
      |> put_configured_opt(config, :retry)

    with :ok <- validate_llm_request_options(agent_opts[:llm_request_options]),
         {:ok, hooks} <- Hooks.normalize(agent_opts[:hooks]),
         {:ok, snapshot} <- load_snapshot(agent_opts[:session_store], agent_opts),
         {:ok, durable} <- load_durable(agent_opts, snapshot),
         model = restore_value(agent_opts, :model, snapshot && snapshot.model),
         {:ok, compaction} <- Compaction.new(agent_opts[:compactor], agent_opts[:background_compaction], model) do
      agent_opts =
        agent_opts
        |> Keyword.put(:model, model)
        |> Keyword.put(:hooks, hooks)
        |> Keyword.put(:max_tokens, agent_opts[:max_tokens] || (agent_opts[:llm_request_options] || [])[:max_tokens])
        |> Keyword.put(:restored_snapshot, snapshot)
        |> Keyword.put(:restored_durable, durable)
        |> Keyword.put(:compaction, compaction)

      case link_mode do
        :link -> GenServer.start_link(__MODULE__, agent_opts, gen_opts)
        :nolink -> GenServer.start(__MODULE__, agent_opts, gen_opts)
      end
    end
  end

  defp validate_llm_request_options(nil), do: :ok

  defp validate_llm_request_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, {:invalid_llm_request_options, opts}}
  end

  defp validate_llm_request_options(opts), do: {:error, {:invalid_llm_request_options, opts}}

  defp put_configured_opt(opts, config, key, default_fun \\ fn -> nil end) do
    Keyword.put_new_lazy(opts, key, fn ->
      Keyword.get_lazy(config, key, fn ->
        Application.get_env(:condukt, key, default_fun.())
      end)
    end)
  end

  # `max_tokens/0` postdates the behaviour, so an agent module compiled against
  # an earlier version still resolves rather than failing to start.
  defp agent_max_tokens(agent_module) do
    if function_exported?(agent_module, :max_tokens, 0), do: agent_module.max_tokens()
  end

  defp agent_sandbox(agent_module) do
    if function_exported?(agent_module, :sandbox, 0) do
      agent_module.sandbox()
    end
  end

  defp agent_runtime(agent_module) do
    if function_exported?(agent_module, :runtime, 0) do
      agent_module.runtime()
    else
      Native
    end
  end

  defp agent_subagents(agent_module) do
    if function_exported?(agent_module, :subagents, 0) do
      agent_module.subagents()
    else
      []
    end
  end

  defp agent_hooks(agent_module) do
    if function_exported?(agent_module, :hooks, 0), do: agent_module.hooks(), else: []
  end

  defp agent_secrets(agent_module) do
    if function_exported?(agent_module, :secrets, 0) do
      agent_module.secrets()
    end
  end

  defp agent_mcp_servers(agent_module) do
    if function_exported?(agent_module, :mcp_servers, 0) do
      agent_module.mcp_servers()
    else
      []
    end
  end

  @doc """
  Runs a prompt synchronously, returning the final response.

  Returns `{:error, :already_streaming}` while another caller's turn runs. A
  turn started from queued input, such as a follow-up or a background
  sub-agent's report, has no caller, so the prompt waits for it instead.

  Returns `{:error, {:session_exit, reason}}` when the session process cannot
  complete the call because it exits, is missing, or exceeds the call timeout.

  With `:request_id`, a retry of the same id returns the first outcome instead
  of running again, and resumes the run when the previous process died in it.
  See the Sessions and Persistence guide.
  """
  def run(agent, prompt, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    call_session(agent, {:run, prompt, attach_trace_context(opts)}, timeout)
  end

  defp call_session(agent, request, timeout) do
    case session_destination(agent) do
      nil ->
        {:error, {:session_exit, {:noproc, {GenServer, :call, [agent, request, timeout]}}}}

      destination ->
        monitor_ref = Process.monitor(destination)
        alias_ref = :erlang.alias([:reply])
        send(destination, {:"$gen_call", {self(), alias_ref}, request})

        receive do
          {^alias_ref, result} ->
            :erlang.unalias(alias_ref)
            Process.demonitor(monitor_ref, [:flush])
            result

          {:DOWN, ^monitor_ref, :process, ^destination, reason} ->
            :erlang.unalias(alias_ref)
            {:error, {:session_exit, reason}}
        after
          timeout ->
            :erlang.unalias(alias_ref)
            Process.demonitor(monitor_ref, [:flush])
            {:error, {:session_exit, :timeout}}
        end
    end
  end

  defp session_destination(pid) when is_pid(pid), do: pid

  defp session_destination(name) when is_atom(name), do: Process.whereis(name)

  defp session_destination({:global, name}) do
    case :global.whereis_name(name) do
      :undefined -> nil
      pid -> pid
    end
  end

  defp session_destination({:via, module, name}) do
    case module.whereis_name(name) do
      :undefined -> nil
      pid -> pid
    end
  end

  defp session_destination({name, node}) when is_atom(name) and is_atom(node), do: {name, node}

  @doc """
  Continues the run the session's previous process died in.

  Only a session whose store keeps a journal (see `Condukt.SessionStore`) can
  have an interrupted run; `interrupted/1` says whether this one does. The run
  picks up after its last stored step: an interrupted model request is made
  again, a tool call that was interrupted runs again only when its tool is
  replay-safe (`Condukt.Tool`), and otherwise the model gets an error result
  saying the call was interrupted. A run restarted more than the session's
  `:restart_limit` times in a row without progress ends with
  `{:error, {:restart_limit, restarts}}` instead.

  Returns the run's result like `run/3`, or `{:error, :nothing_to_resume}`.
  `resume_stream/2` streams the run instead.
  """
  def resume(agent, opts \\ []) do
    timeout = opts[:timeout] || @default_timeout
    call_session(agent, {:resume, attach_trace_context(opts)}, timeout)
  end

  @doc """
  Describes the run the session's previous process died in, or `nil`.

  Returns `%{run_id: id, request_id: id_or_nil, restarts: count}`.
  """
  def interrupted(agent) do
    call_session(agent, :interrupted, @default_timeout)
  end

  @doc """
  Streams a prompt, returning an enumerable of events.

  With `:request_id`, a retry continues or replays the request as `run/3`
  does. When the session process dies before the stream ends, the stream
  emits `{:error, {:session_exit, reason}}` and ends.
  """
  def stream(agent, prompt, opts \\ []) do
    opts = attach_trace_context(opts)
    stream_events(agent, &{:stream, prompt, opts, &1}, opts[:timeout] || @default_timeout)
  end

  @doc """
  Continues the run the session's previous process died in, streaming it.

  The streaming counterpart of `resume/2`, returning the same events as
  `stream/3`. Tool results the resume decides, interrupted ones included, are
  emitted before the run goes on; a final answer that was stored but never
  delivered is emitted as one `{:text, answer}`. Emits `{:error, reason}` and
  ends when there is nothing to resume, another run is streaming, the run
  reached its restart limit, or its restart cannot be stored.
  """
  def resume_stream(agent, opts \\ []) do
    opts = attach_trace_context(opts)
    stream_events(agent, &{:resume_stream, opts, &1}, opts[:timeout] || @default_timeout)
  end

  defp stream_events(agent, request, timeout) do
    Stream.resource(
      fn ->
        ref = make_ref()
        session = GenServer.whereis(agent)
        # Fails, as before, when there is no session to monitor.
        :ok = GenServer.call(agent, {:subscribe, self(), ref})
        monitor = Process.monitor(session)
        :ok = GenServer.cast(agent, request.(ref))
        {ref, monitor}
      end,
      fn
        {:ended, acc} ->
          {:halt, acc}

        {ref, monitor} = acc ->
          # A session that dies mid-stream never sends `:done`.
          receive do
            {^ref, :done} -> {:halt, acc}
            {^ref, event} -> {[event], acc}
            {:DOWN, ^monitor, :process, _pid, reason} -> {[{:error, {:session_exit, reason}}], {:ended, acc}}
          after
            timeout -> {[{:error, :timeout}], acc}
          end
      end,
      fn
        {:ended, {ref, monitor}} -> unsubscribe(agent, ref, monitor)
        {ref, monitor} -> unsubscribe(agent, ref, monitor)
      end
    )
  end

  defp unsubscribe(agent, ref, monitor) do
    Process.demonitor(monitor, [:flush])
    GenServer.cast(agent, {:unsubscribe, self(), ref})
  end

  @doc false
  # Subscribes the caller under `ref` and starts a streaming turn, for callers
  # that consume the events themselves, such as a foreground sub-agent call.
  def stream_to(agent, prompt, opts, ref) do
    :ok = GenServer.call(agent, {:subscribe, self(), ref})
    GenServer.cast(agent, {:stream, prompt, opts, ref})
  end

  @doc false
  # Publishes an event from a sub-agent where the session's own events go: the
  # streaming turn `turn_ref` names, or with `nil` the notifier only, for
  # background sub-agents that outlive the turn that started them.
  def forward_event(session, turn_ref, event) do
    GenServer.cast(session, {:subagent_event, turn_ref, event})
  end

  @doc false
  # Publishes `{:tool_output, tool_call_id, chunk}` from a call of the turn
  # `turn_ref` names. See `Condukt.Tool.output/2`.
  def tool_output(session, turn_ref, event) do
    GenServer.cast(session, {:tool_output, turn_ref, event})
  end

  @doc false
  # Whether a turn runs or input other than reports waits to start one.
  def busy?(agent) do
    GenServer.call(agent, :busy?)
  end

  @doc false
  # Whether `turn_ref` is the turn still running. A tool that runs past an
  # abort, as `on_abort: :finish` lets it, asks before it returns something
  # the aborted turn would drop.
  def turn_running?(agent, turn_ref) do
    GenServer.call(agent, {:turn_running?, turn_ref}, :infinity)
  end

  @doc false
  # Whether queued input starts turns here, which only native loops do.
  def native_runtime?(agent) do
    GenServer.call(agent, :native_runtime?)
  end

  @doc false
  # Queues a background sub-agent's report as input under `tag`. It starts a
  # turn when the session is idle, or follows the current one, and an abort
  # keeps it. `withdraw_report/2` removes it while it still waits.
  def report(session, tag, text) do
    GenServer.cast(session, {:report, tag, text})
  end

  @doc false
  def withdraw_report(session, tag) do
    GenServer.cast(session, {:withdraw_report, tag})
  end

  @doc false
  # Records in the view what a background sub-agent's manager reports of it:
  # its name, role, session id, spawning call, and status, or `nil` once it
  # is gone.
  def background_changed(session, name, entry) do
    GenServer.cast(session, {:background_subagent, name, entry})
  end

  @doc false
  # Records in the view the message a background sub-agent's turn started
  # from, `{:run_started, message}`, or steering that joined it,
  # `{:input, message}`. Nothing is published: the notifier's events are
  # unchanged.
  def background_input(session, name, change) do
    GenServer.cast(session, {:background_input, name, change})
  end

  @doc false
  # Takes an input submitted by id, see `Condukt.Sessions.submit/3`.
  def submit(agent, input) do
    call_session(agent, {:submit, input}, @default_timeout)
  end

  @doc """
  Returns the session's current `Condukt.Session.View`: its history, the turn
  in flight with its partial answer and running tools, queued input, and agent
  configuration, free of secrets.

  Pair it with numbered changes from a notifier on another node; see
  `Condukt.Notifiers.PubSub`. In the same node, or with the session's pid,
  `watch/1` returns the view and subscribes in one step.
  """
  def view(agent) do
    GenServer.call(agent, :view)
  end

  @doc """
  Returns the session's current `Condukt.Session.View` and subscribes the
  caller to the changes after it.

  The caller receives `{:condukt_change, session_id, epoch, seq, change}` for
  every change, starting with the one numbered after the view's `seq`, and
  applies them with `Condukt.Session.View.advance/4`. Nothing between the view
  and the first change is lost or repeated. Watching again only returns the
  current view. The subscription ends with `unwatch/1` or the caller's exit.
  """
  def watch(agent) do
    GenServer.call(agent, {:watch, self()})
  end

  @doc "Stops the changes `watch/1` subscribed the caller to."
  def unwatch(agent) do
    GenServer.cast(agent, {:unwatch, self()})
  end

  @doc """
  Returns the conversation history.
  """
  def history(agent) do
    GenServer.call(agent, :history)
  end

  @doc """
  Returns the unique identifier for this session.

  Sessions are identified by a UUIDv7 generated when the session starts, or by
  the value passed via the `:id` option to `start_link/2` / `start/2`. The id
  is included in telemetry metadata so subscribers can group all events
  emitted by a single agentic run.
  """
  def id(agent) do
    GenServer.call(agent, :id)
  end

  @doc """
  Clears the conversation history.
  """
  def clear(agent) do
    GenServer.call(agent, :clear)
  end

  @doc """
  Aborts the current operation.

  Replies to a running caller with `{:error, :aborted}`, or closes its stream
  after that error. The turn's process is shut down before this returns, and
  the processes linked below it go down with it: running tool calls and what
  they own, such as a foreground sub-agent's session. Tools that ask to
  `:finish` (see `Condukt.Tool`) run to the end instead. Side effects already
  made are not rolled back, and late events and results from the turn cannot
  affect the session or a replacement turn.
  """
  def abort(agent) do
    GenServer.call(agent, :abort)
  end

  @doc """
  Delivers a signal to the running turn's parked tool calls.

  `agent` is a session pid, name, or the id of a session started with
  `Condukt.Sessions`. An id reaches whatever sessions the configured
  `Condukt.Sessions.Registry` sees, which with a cluster-wide adapter includes
  other nodes. `kind` is a `Condukt.Signal` module, whose `cast/1`
  checks `value` in the calling process.

  Returns `:ok` when the value is kept for the call parked on `{kind, key}`,
  which wakes, or for the first call that parks on it later in the turn.
  Otherwise returns `{:error, reason}`:

    * `:duplicate` - the key already holds a value, as for a webhook retry.
    * `{:invalid, reason}` - `cast/1` rejected the value; nothing is kept.
    * `:closed` - no turn is running, or the key's wait is over: its deadline
      came first, another of its keys woke it, or its turn ended. Keys stay
      closed for the rest of the session.
    * `:inbox_full` - the turn already holds 100 signals for keys no call has
      parked on.
    * `:not_found` - no session answers under `agent`.

  Treat `:duplicate` and `:closed` as final answers to the sender. Nothing
  checks who sends a signal, so authenticate senders in the host.
  """
  def signal(agent, kind, key, value) do
    with {:cast, {:ok, value}} <- {:cast, Signal.cast(kind, key, value)},
         {:error, {:session_exit, _reason}} <-
           call_session(signal_target(agent), {:signal, {kind, key}, value}, @default_timeout) do
      {:error, :not_found}
    else
      {:cast, {:error, reason}} -> {:error, {:invalid, reason}}
      result -> result
    end
  end

  defp signal_target(id) when is_binary(id), do: Condukt.Sessions.whereis(id)
  defp signal_target(agent), do: agent

  @doc """
  Returns what a parked turn waits for, or `nil` while it runs or is idle.

  A turn is waiting once each of its pending tool calls is parked and its
  worker blocks until a signal or a deadline wakes one. The result is
  `%{tool_calls: [%{tool_call_id: id, tool: name, signals: keys, until: deadline}], wake_at: deadline}`,
  where `wake_at` is the earliest deadline or `nil`. The session publishes the
  same map as a `{:waiting, map}` event whenever it changes.
  """
  def waiting(agent) do
    GenServer.call(agent, :waiting)
  end

  @doc """
  Runs the configured compactor against the current message history.

  No-op when no compactor is configured. The compacted snapshot is
  immediately persisted if a session store is configured. With background
  compaction enabled, waits without blocking the session process, and returns
  `{:error, :already_streaming}` if a turn is active. Returns
  `{:error, :interrupted}` while the session has an interrupted run, which
  `resume/2` continues and a new run gives up.
  """
  def compact(agent) do
    GenServer.call(agent, :compact, @default_timeout)
  end

  @doc """
  Injects a steering message.

  A running native turn takes it before its next model request, after the
  current tool round. An idle session starts a turn with it.
  """
  def steer(agent, message) do
    GenServer.call(agent, {:steer, message})
  end

  @doc """
  Queues a follow-up message.

  It starts a turn once the running turn finishes, or at once when the session
  is idle. Turns started this way stream their events to the notifier and
  `handle_event/2`. Aborting withdraws queued messages.
  """
  def follow_up(agent, message) do
    GenServer.call(agent, {:follow_up, message})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    agent_module = Keyword.fetch!(opts, :agent_module)
    session_store = Keyword.get(opts, :session_store)
    snapshot = Keyword.fetch!(opts, :restored_snapshot)

    case agent_module.init(opts) do
      {:ok, user_state} ->
        configured_system_prompt = restore_value(opts, :system_prompt, snapshot && snapshot.system_prompt)
        cwd = Keyword.fetch!(opts, :cwd)
        id = Keyword.get(opts, :id) || SessionID.generate()

        with {:runtime, {:ok, runtime}} <- {:runtime, resolve_runtime(opts[:runtime])},
             {:sandbox, {:ok, sandbox}} <- {:sandbox, resolve_sandbox(opts[:sandbox], cwd, id)},
             {:secrets, {:ok, secrets}} <- {:secrets, Secrets.resolve(opts[:secrets])},
             {:mcp, {:ok, mcp_registry}} <-
               {:mcp, MCP.start_all(Keyword.get(opts, :mcp_servers, []))} do
          project_context = load_project_context(opts, sandbox)
          sandbox = Sandbox.Lease.start(sandbox, Keyword.take(opts, [:lease_interval]))
          emit_secret_resolve(id, agent_module, secrets)
          subagents = normalize_subagents(Keyword.get(opts, :subagents, []))
          {:ok, subagent_supervisor} = maybe_start_subagent_supervisor(subagents)
          # Each turn runs as a child of this supervisor, so the turn and
          # everything linked below it go down with the session.
          {:ok, turn_supervisor} = Task.Supervisor.start_link()
          configured_tools = Keyword.fetch!(opts, :tools)
          tools = configured_tools ++ MCP.tools(mcp_registry)

          state =
            %__MODULE__{
              id: id,
              # Opaque to Condukt and persisted with the snapshot, so a host
              # holding sessions for more than one person can tell whose is
              # whose after a restart.
              actor: Keyword.get(opts, :actor),
              notifier: Keyword.get(opts, :notifier),
              created_at: (snapshot && snapshot.created_at) || DateTime.utc_now(),
              pid: self(),
              agent_module: agent_module,
              runtime: runtime,
              llm: %{
                model: opts[:model],
                thinking_level: restore_value(opts, :thinking_level, snapshot && snapshot.thinking_level),
                max_tokens: opts[:max_tokens],
                api_key: opts[:api_key],
                base_url: opts[:base_url],
                request_options: opts[:llm_request_options],
                retry: Retry.normalize(opts[:retry])
              },
              configured_system_prompt: configured_system_prompt,
              system_prompt: Context.compose_system_prompt(configured_system_prompt, project_context.prompt),
              tools: tools ++ Subagent.tools(subagents, subagent_supervisor),
              hooks: Keyword.fetch!(opts, :hooks),
              subagents: subagents,
              subagent_supervisor: subagent_supervisor,
              turn_supervisor: turn_supervisor,
              cwd: cwd,
              sandbox: sandbox,
              secrets: secrets,
              mcp_registry: mcp_registry,
              session_store: session_store,
              session_store_opts: session_store_opts(opts),
              compaction: Keyword.fetch!(opts, :compaction),
              redactor: opts[:redactor],
              project_context: project_context,
              user_state: user_state,
              inbox: Keyword.get(opts, :inbox),
              assigns: Keyword.get(opts, :assigns, %{})
            }
            |> restore_messages(snapshot)
            |> restore_durable(Keyword.fetch!(opts, :restored_durable))

          :ok = join_sessions(state, Keyword.get(opts, :parent))
          {:ok, start_viewer(state)}
        else
          {:runtime, {:error, reason}} ->
            {:stop, {:runtime_init_failed, reason}}

          {:sandbox, {:error, reason}} ->
            {:stop, {:sandbox_init_failed, reason}}

          {:secrets, {:error, reason}} ->
            {:stop, {:secrets_init_failed, reason}}

          {:mcp, {:error, reason}} ->
            {:stop, {:mcp_init_failed, reason}}
        end

      {:stop, reason} ->
        {:stop, reason}
    end
  end

  defp resolve_sandbox(nil, cwd, session_id) do
    Sandbox.new(Sandbox.Local, cwd: cwd, id: session_id, owner_pid: self())
  end

  defp resolve_sandbox(module, _cwd, session_id) when is_atom(module) do
    Sandbox.resolve({module, [id: session_id, owner_pid: self()]})
  end

  defp resolve_sandbox({module, opts}, _cwd, session_id) when is_atom(module) and is_list(opts) do
    Sandbox.resolve(
      {module,
       opts
       |> Keyword.put_new(:id, session_id)
       |> Keyword.put_new(:owner_pid, self())}
    )
  end

  defp resolve_sandbox(spec, _cwd, _session_id), do: Sandbox.resolve(spec)

  defp resolve_runtime(nil), do: {:ok, {Native, []}}
  defp resolve_runtime(Native), do: {:ok, {Native, []}}

  defp resolve_runtime({Native, opts}) when is_list(opts) do
    {:ok, {Native, opts}}
  end

  defp resolve_runtime(module) when is_atom(module) do
    validate_runtime_module(module, [])
  end

  defp resolve_runtime({module, opts}) when is_atom(module) and is_list(opts) do
    validate_runtime_module(module, opts)
  end

  defp resolve_runtime(runtime), do: {:error, {:invalid_runtime, runtime}}

  defp validate_runtime_module(module, opts) do
    cond do
      Code.ensure_loaded?(module) and function_exported?(module, :run, 3) ->
        {:ok, {module, opts}}

      Code.ensure_loaded?(module) ->
        {:error, {:runtime_missing_run_callback, module}}

      true ->
        {:error, {:runtime_not_loaded, module}}
    end
  end

  defp normalize_subagents(subagents) do
    Enum.map(subagents, fn
      {role, module} when is_atom(role) and is_atom(module) ->
        {role, {module, []}}

      {role, {module, opts}} when is_atom(role) and is_atom(module) and is_list(opts) ->
        {role, {module, opts}}

      {role, opts} when is_atom(role) and is_list(opts) ->
        {role, {Condukt.AnonymousAgent, anonymous_subagent_opts!(opts)}}
    end)
  end

  defp anonymous_subagent_opts!(opts) do
    if Keyword.keyword?(opts) do
      Keyword.put_new(opts, :load_project_instructions, false)
    else
      raise ArgumentError, "anonymous sub-agent registration must be a keyword list"
    end
  end

  defp maybe_start_subagent_supervisor([]), do: {:ok, nil}

  defp maybe_start_subagent_supervisor(_subagents) do
    DynamicSupervisor.start_link(strategy: :one_for_one)
  end

  @impl true
  def handle_call({:run, prompt, opts}, from, state) do
    cond do
      state.turn.streaming and state.turn.queued ->
        {:noreply, sync_queue(%{state | turn: Turn.enqueue(state.turn, {prompt, opts, {:run, from}})})}

      state.turn.streaming or not is_nil(state.compaction.waiter) ->
        {:reply, {:error, :already_streaming}, state}

      true ->
        {:noreply, start_run(state, prompt, opts, from)}
    end
  end

  def handle_call({:resume, opts}, from, state) do
    cond do
      state.turn.streaming or not is_nil(state.compaction.waiter) ->
        {:reply, {:error, :already_streaming}, state}

      is_nil(state.durable.interrupted) ->
        {:reply, {:error, :nothing_to_resume}, state}

      true ->
        {:noreply, start_resume(state, {:run, from}, opts)}
    end
  end

  def handle_call(:interrupted, _from, state) do
    {:reply, Durable.interrupted_info(state.durable), state}
  end

  # The session process stores every record, so a superseded turn's records
  # are fenced by its reference and the journal keeps one order.
  def handle_call({:journal, ref, records}, _from, state) do
    if state.turn.streaming and ref == state.turn.abort_ref do
      {:reply, append_to_journal(state, records), state}
    else
      {:reply, {:error, :aborted}, state}
    end
  end

  def handle_call({:subscribe, pid, ref}, _from, state) do
    # Monitored, because the only other way out of this list is an explicit
    # unsubscribe and a subscriber that crashes never sends one. Without this a
    # session accumulates dead pids for as long as it lives and keeps sending
    # to every one of them.
    monitor = Process.monitor(pid)
    {:reply, :ok, %{state | turn: Turn.subscribe(state.turn, pid, ref, monitor)}}
  end

  # The view process replies. It takes these requests from the session, in
  # line with every change the session sent it before, so the view holds what
  # the session did up to this request, and a watcher is added at the very
  # change the view ends at, with nothing lost or repeated after it.
  def handle_call(:view, from, state) do
    GenServer.cast(state.viewer, {:view, from})
    {:noreply, state}
  end

  def handle_call({:watch, pid}, from, state) do
    GenServer.cast(state.viewer, {:watch, pid, from})
    {:noreply, state}
  end

  def handle_call(:history, _from, state) do
    {:reply, state.messages, state}
  end

  def handle_call(:id, _from, state) do
    {:reply, state.id, state}
  end

  def handle_call(:clear, from, state) do
    state = abort_turn(state)
    compaction = %{Compaction.cancel(state.compaction) | attempted: nil, usage: nil}
    if state.messages != [], do: view_change(state, {:messages, :replace, []})
    if state.durable.interrupted, do: settle_input(state, state.durable.interrupted.input, :aborted)
    state = %{state | messages: [], compaction: compaction, durable: Durable.reset(state.durable)}

    # A journal that could not be cleared still holds runs the cleared history
    # must not get back. An empty snapshot past their ids makes a restart skip
    # them.
    if state.durable.enabled and Durable.clear(state.session_store, session_store_opts(state)) != :ok,
      do: persist_snapshot(state),
      else: persist_or_clear_snapshot(state, :clear)

    reply_after_view(maybe_start_queued_turn(state), from, :ok)
  end

  def handle_call(:abort, from, state) do
    state |> abort_turn() |> maybe_start_queued_turn() |> reply_after_view(from, :ok)
  end

  def handle_call({:take_steering, ref}, _from, state) do
    if state.turn.streaming and ref == state.turn.abort_ref do
      {steering, turn} = Turn.take_steering(state.turn)

      # Steering joins the run's history, so it is stored before the worker
      # gets it. When that fails it stays queued and the run ends.
      case journal_input(state, steering) do
        :ok ->
          state = sync_queue(%{state | turn: turn})
          Enum.each(steering, &view_change(state, {:input, &1}))
          {:reply, {:ok, steering}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :aborted}, state}
    end
  end

  def handle_call(:busy?, _from, state) do
    {:reply, state.turn.streaming or Turn.input_waiting?(state.turn), state}
  end

  def handle_call({:turn_running?, turn_ref}, _from, state) do
    {:reply, state.turn.streaming and turn_ref == state.turn.abort_ref, state}
  end

  def handle_call(:native_runtime?, _from, state) do
    {:reply, match?({Native, _}, state.runtime), state}
  end

  def handle_call(:sync, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call({:park, ref, call, call_state, park}, _from, state) do
    if state.turn.streaming and ref == state.turn.abort_ref do
      case Parking.park(parking(state), call, call_state, park) do
        {:ok, records} -> {:reply, :ok, commit_parking(state, records)}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :aborted}, state}
    end
  end

  def handle_call({:signal, key, value}, _from, state) do
    with true <- state.turn.streaming,
         {:ok, records} <- Parking.signal(parking(state), key, value) do
      {:reply, :ok, commit_parking(state, records)}
    else
      false -> {:reply, {:error, :closed}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:waiting, _from, state) do
    reply =
      case state.turn.parking do
        %Parking{blocked: true} = parking -> waiting_info(parking)
        _other -> nil
      end

    {:reply, reply, state}
  end

  # The worker takes the woken calls of its parked round. With none woken it
  # blocks until the session sends `{:parking_ready, ref}`.
  def handle_call({:take_ready, ref}, _from, state) do
    with true <- state.turn.streaming and ref == state.turn.abort_ref,
         %Parking{} = parking <- state.turn.parking do
      if Parking.ready?(parking) do
        {resumes, parking} = Parking.take_ready(parking)
        {:reply, {:ok, resumes}, put_parking(state, %{parking | blocked: false, published: nil})}
      else
        {:reply, {:ok, %{}}, publish_waiting(put_parking(state, %{parking | blocked: true}))}
      end
    else
      false -> {:reply, {:error, :aborted}, state}
      nil -> {:reply, {:ok, %{}}, state}
    end
  end

  # The interrupted run's journal follows the history it started from, so a
  # snapshot of a compacted history would make a restart drop the run.
  def handle_call(:compact, _from, %{durable: %{interrupted: run}} = state) when run != nil do
    {:reply, {:error, :interrupted}, state}
  end

  def handle_call(:compact, from, state) do
    cond do
      not Compaction.enabled?(state.compaction) ->
        compacted = maybe_compact(state)
        persist_snapshot(compacted)
        {:reply, :ok, view_history_changed(compacted, state.messages)}

      state.turn.streaming or not is_nil(state.compaction.waiter) ->
        {:reply, {:error, :already_streaming}, state}

      true ->
        compaction = Compaction.start(state.compaction, state.messages, compaction_metadata(state))
        waiter = {from, compaction_overhead(state), compaction_metadata(state), :manual}
        {:noreply, %{state | compaction: %{compaction | waiter: waiter}}}
    end
  end

  def handle_call({:compaction_checkpoint, ref, messages, trace_context, phase}, from, state) do
    if state.turn.streaming and ref == state.turn.abort_ref do
      compaction = %{state.compaction | trace_context: trace_context}
      state = %{state | messages: messages, compaction: compaction}
      compaction_checkpoint_reply(state, from, compaction_overhead(state), compaction_metadata(state), phase)
    else
      {:reply, {:error, :aborted}, state}
    end
  end

  def handle_call({:steer, message}, _from, state) do
    msg = Message.user(message)
    {:reply, :ok, maybe_start_queued_turn(%{state | turn: Turn.steer(state.turn, msg)})}
  end

  def handle_call({:follow_up, message}, _from, state) do
    msg = Message.user(message)
    {:reply, :ok, maybe_start_queued_turn(%{state | turn: Turn.follow_up(state.turn, msg)})}
  end

  def handle_call({:submit, input}, _from, state) do
    case Turn.submit(state.turn, input, Message.user(input.text)) do
      {:ok, turn} -> {:reply, :ok, maybe_start_queued_turn(%{state | turn: turn})}
      {:error, :duplicate} -> {:reply, {:error, :duplicate}, state}
    end
  end

  @impl true
  def handle_cast({:stream, prompt, opts, subscriber_ref}, state) when state.turn.streaming and state.turn.queued do
    {:noreply, sync_queue(%{state | turn: Turn.enqueue(state.turn, {prompt, opts, {:stream, subscriber_ref}})})}
  end

  def handle_cast({:stream, _prompt, _opts, subscriber_ref}, state)
      when state.turn.streaming or not is_nil(state.compaction.waiter) do
    broadcast_subscribers(state, subscriber_ref, {:error, :already_streaming})
    broadcast_subscribers(state, subscriber_ref, :done)
    {:noreply, state}
  end

  def handle_cast({:stream, prompt, opts, subscriber_ref}, state) do
    {:noreply, start_stream(state, prompt, opts, subscriber_ref)}
  end

  def handle_cast({:resume_stream, _opts, subscriber_ref}, state)
      when state.turn.streaming or not is_nil(state.compaction.waiter) do
    {:noreply, end_stream(state, subscriber_ref, {:error, :already_streaming})}
  end

  def handle_cast({:resume_stream, _opts, subscriber_ref}, %{durable: %{interrupted: nil}} = state) do
    {:noreply, end_stream(state, subscriber_ref, {:error, :nothing_to_resume})}
  end

  def handle_cast({:resume_stream, opts, subscriber_ref}, state) do
    {:noreply, start_resume(state, {:stream, subscriber_ref}, opts)}
  end

  def handle_cast({:report, tag, text}, state) do
    {:noreply, maybe_start_queued_turn(%{state | turn: Turn.report(state.turn, tag, Message.user(text))})}
  end

  def handle_cast({:withdraw_report, tag}, state) do
    {:noreply, sync_queue(%{state | turn: Turn.withdraw_report(state.turn, tag)})}
  end

  def handle_cast({:unwatch, pid}, state) do
    GenServer.cast(state.viewer, {:unwatch, pid})
    {:noreply, state}
  end

  def handle_cast({:unsubscribe, pid, ref}, state) do
    {turn, monitors} = Turn.unsubscribe(state.turn, pid, ref)
    Enum.each(monitors, &Process.demonitor(&1, [:flush]))
    {:noreply, %{state | turn: turn}}
  end

  def handle_cast({:broadcast_event, turn_ref, event, ref}, state) do
    if turn_ref == state.turn.abort_ref do
      state = broadcast(state, ref, event)
      {:noreply, maybe_dispatch_event(state, event)}
    else
      {:noreply, state}
    end
  end

  # A turn run without streaming publishes no events, as before, but its
  # steps and tool calls still reach the view as each finishes.
  def handle_cast({:view_event, turn_ref, event}, state) do
    if turn_ref == state.turn.abort_ref do
      view_change(state, event)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # Streamed like the turn's own events, or, for a turn run without
  # streaming, to the view only, as its other steps are.
  def handle_cast({:tool_output, turn_ref, event}, state) do
    case state.turn.recipient do
      _recipient when turn_ref != state.turn.abort_ref -> {:noreply, state}
      {:stream, ref} -> {:noreply, broadcast(state, ref, event)}
      _run -> {:noreply, tap(state, &view_change(&1, event))}
    end
  end

  def handle_cast({:background_subagent, name, entry}, state) do
    view_change(state, {:background, name, entry})
    {:noreply, state}
  end

  def handle_cast({:background_input, _name, _change} = input, state) do
    GenServer.cast(state.viewer, input)
    {:noreply, state}
  end

  # A background sub-agent's events go to the notifier, as before, and build
  # its run in the view; the view process does both, in one order.
  def handle_cast({:subagent_event, nil, event}, state) do
    GenServer.cast(state.viewer, {:background_subagent_event, event})
    {:noreply, state}
  end

  def handle_cast({:subagent_event, turn_ref, event}, state) do
    case state.turn.recipient do
      {:stream, ref} when turn_ref == state.turn.abort_ref -> {:noreply, broadcast(state, ref, event)}
      _other -> {:noreply, state}
    end
  end

  def handle_cast({:compaction_usage, ref, response, messages}, state) do
    if ref == state.turn.abort_ref do
      {:noreply, %{state | compaction: Compaction.usage(state.compaction, response, messages)}}
    else
      {:noreply, state}
    end
  end

  # Woken calls the worker ran that returned results instead of parking again.
  def handle_cast({:parking_done, turn_ref, ids}, state) do
    if turn_ref == state.turn.abort_ref and state.turn.parking do
      {:noreply, commit_parking(state, Enum.map(ids, &{:done, &1}))}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:run_complete, turn_ref, from, result}, state) do
    if turn_ref == state.turn.abort_ref do
      handle_cast({:run_complete, from, result}, state)
    else
      {:noreply, state}
    end
  end

  # A run started from input is a resumed one: input is otherwise streamed.
  def handle_cast({:run_complete, from, {result, messages, assigns}}, state) do
    settle_input(state, state.turn.input, result)

    # A failed native run may have already adopted a prefix at a checkpoint.
    # Its original captured history must not restore that discarded prefix.
    messages =
      if match?({:error, _}, result) and Compaction.enabled?(state.compaction), do: state.messages, else: messages

    state = state |> adopt_turn_messages(messages, assigns) |> view_run_finished(run_error(result))
    state = finish_turn(state)

    state =
      if match?({:ok, _}, result) or not Compaction.enabled?(state.compaction),
        do: state |> maybe_compact() |> view_history_changed(state.messages),
        else: state

    # Stored before the caller hears, so a caller that got the answer never
    # finds the run interrupted.
    state = persist_run(state, result)
    GenServer.reply(from, result)
    {:noreply, maybe_start_queued_turn(state)}
  end

  def handle_cast({:stream_complete, turn_ref, ref, result}, state) do
    if turn_ref == state.turn.abort_ref do
      handle_cast({:stream_complete, ref, result}, state)
    else
      {:noreply, state}
    end
  end

  def handle_cast({:stream_complete, ref, {:ok, messages, response, assigns}}, state) do
    settle_input(state, state.turn.input, {:ok, response})
    state = broadcast(state, ref, :done)
    state = state |> adopt_turn_messages(messages, assigns) |> view_run_finished(nil)
    state = finish_turn(state)
    state = state |> maybe_compact() |> view_history_changed(state.messages)
    {:noreply, maybe_start_queued_turn(persist_run(state, {:ok, response}))}
  end

  # A resumed stream that fails keeps what the interrupted run had stored,
  # unless compaction already replaced it, as in `run_complete`.
  def handle_cast({:stream_complete, ref, {:error, reason, messages}}, state) do
    settle_input(state, state.turn.input, {:error, reason})
    state = broadcast(state, ref, :done)
    messages = if Compaction.enabled?(state.compaction), do: state.messages, else: messages
    state = %{state | messages: messages} |> view_run_finished(reason) |> finish_turn()
    {:noreply, maybe_start_queued_turn(persist_run(state, {:error, reason}))}
  end

  def handle_cast({:stream_complete, ref, result}, state) do
    settle_input(state, state.turn.input, {:error, run_error(result)})
    state = broadcast(state, ref, :done) |> view_run_finished(run_error(result))
    state = finish_turn(state)
    state = if state.durable.current, do: persist_run(state, result), else: state
    {:noreply, maybe_start_queued_turn(state)}
  end

  @impl true
  def handle_info({ref, result}, %{compaction: %{task: %Task{ref: ref}}} = state) do
    compaction_finished(%{state | compaction: Compaction.complete(state.compaction, ref, result)})
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{compaction: %{task: %Task{ref: ref}}} = state) do
    Logger.warning("compaction worker exited: #{inspect(reason)}")
    compaction_finished(%{state | compaction: Compaction.complete(state.compaction, ref, {:error, reason})})
  end

  def handle_info({:compaction_timeout, ref}, %{compaction: %{task: %Task{ref: ref}}} = state) do
    compaction = %{Compaction.cancel(state.compaction) | result: {:error, :timeout}}
    compaction_finished(%{state | compaction: compaction})
  end

  def handle_info({:park_deadline, ref}, %{turn: %{abort_ref: ref, parking: %Parking{} = parking}} = state) do
    records = Parking.expire(parking, System.os_time(:millisecond))
    {:noreply, commit_parking(state, records)}
  end

  # A worker that crashed sent no result, so its turn ends here with the crash
  # as its error. One that finished or was aborted is no longer the turn's
  # worker when its monitor fires: its result came first, or the abort ended
  # the turn.
  def handle_info({:DOWN, _monitor, :process, worker, reason}, %{turn: %{worker: worker}} = state)
      when is_pid(worker) do
    reason = exit_summary(state, crash_reason(reason))
    Logger.error("session #{state.id} run worker exited: #{inspect(reason)}")
    {:noreply, worker_exited(state, {:error, {:turn_crashed, reason}})}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    {:noreply, %{state | turn: Turn.drop_monitored(state.turn, monitor)}}
  end

  # Takes the inputs the inbox stored for this session, as it starts and
  # whenever `Condukt.Sessions.submit/3` stores another. Inputs the session
  # already took are dropped as duplicates.
  def handle_info({Condukt.Sessions, :drain}, %{inbox: inbox} = state) when not is_nil(inbox) do
    case Inbox.take(inbox, state.id) do
      {:ok, inputs} ->
        {:noreply, maybe_start_queued_turn(%{state | turn: Enum.reduce(inputs, state.turn, &take_input/2)})}

      {:error, reason} ->
        Logger.warning("session #{state.id} could not take its stored input: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  # A drained session leaves its parked calls, and the sandbox processes
  # they follow, for the node that takes the session over.
  def terminate(reason, state) do
    if reason != {:shutdown, :drain}, do: cancel_parked(state)
    settle_inputs(state, :aborted)
    if state.mcp_registry, do: MCP.stop_all(state.mcp_registry)
    stop_subagent_supervisor(state.subagent_supervisor)
    Compaction.stop(state.compaction)
    :ok
  end

  defp stop_subagent_supervisor(nil), do: :ok

  defp stop_subagent_supervisor(supervisor) do
    if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
    :ok
  end

  # ============================================================================
  # Agent Loop Implementation
  # ============================================================================

  defp do_run(%{runtime: {Native, _}} = state, prompt, opts) do
    do_native_run(state, prompt, opts)
  end

  defp do_run(state, prompt, opts) do
    do_runtime_run(state, prompt, opts)
  end

  defp do_native_run(state, prompt, opts) do
    max_turns = opts[:max_turns] || @default_max_turns
    images = opts[:images] || []

    user_message = Message.user(prompt, images)
    messages = state.messages ++ [user_message]

    Telemetry.span(:agent, %{agent: state.agent_module, session_id: state.id}, fn ->
      result = with :ok <- journal_start(state, user_message, max_turns), do: agent_loop(state, messages, max_turns, 0)

      case result do
        {:ok, final_messages, response, final_assigns} ->
          {{:ok, response}, final_messages, final_assigns}

        {:error, reason} ->
          {{:error, reason}, messages, state.assigns}
      end
    end)
  end

  defp do_resume(state, plan) do
    max_turns = plan.max_turns || @default_max_turns

    Telemetry.span(:agent, %{agent: state.agent_module, session_id: state.id}, fn ->
      {state, messages} = resume_tools(state, plan)

      result =
        if plan.step == :answered,
          do: {:ok, messages, extract_text_response(messages), state.assigns},
          else: agent_loop(state, messages, max_turns, plan.turn)

      case result do
        {:ok, final_messages, response, final_assigns} ->
          {{:ok, response}, final_messages, final_assigns}

        {:error, reason} ->
          {{:error, reason}, Durable.close(messages), state.assigns}
      end
    end)
  end

  defp do_stream_resume(state, plan, emit, abort_ref) do
    max_turns = plan.max_turns || @default_max_turns
    emit.(:agent_start)

    Telemetry.span(:agent, %{agent: state.agent_module, session_id: state.id}, fn ->
      {state, messages} = resume_tools(state, plan, emit)

      result =
        if plan.step == :answered,
          do: deliver_answer(state, messages, emit),
          else: streaming_loop(state, messages, max_turns, plan.turn, emit, abort_ref)

      emit.(:agent_end)

      case result do
        {:ok, _messages, _response, _assigns} = ok -> ok
        {:error, reason} -> {:error, reason, Durable.close(messages)}
      end
    end)
  end

  # The answer was stored before the crash, but its stream may have ended
  # before delivering it, so it is emitted whole.
  defp deliver_answer(state, messages, emit) do
    response = extract_text_response(messages)
    emit.({:text, response})
    {:ok, messages, response, state.assigns}
  end

  # Runs the calls that never started or are replay-safe, then puts every
  # result back in the order the model asked for them. A stream also gets the
  # results the resume decided without running anything.
  defp resume_tools(state, plan, emit \\ &noop_emit/1)

  defp resume_tools(state, %{step: :tools} = plan, emit) do
    interrupted = MapSet.new(plan.interrupted, & &1.tool_call_id)

    for {id, name, args} <- plan.calls, MapSet.member?(interrupted, id) do
      emit.({:tool_call, name, id, args})
      emit.({:tool_result, id, Message.tool_result_content(Map.fetch!(plan.results, id))})
    end

    {results, state} =
      case plan.rerun do
        [] ->
          {plan.results, state}

        rerun ->
          calls = Message.assistant(Enum.map(rerun, fn {id, name, args} -> {:tool_call, id, name, args} end))

          case execute_tool_calls(state, calls, plan.prefix, emit) do
            {tool_results, _messages, assigns_diff} ->
              {Map.merge(plan.results, Map.new(tool_results, &{&1.tool_call_id, &1})),
               %{state | assigns: Map.merge(state.assigns, assigns_diff)}}

            {:error, _reason} ->
              {plan.results, state}
          end
      end

    {state,
     plan.prefix ++
       Enum.map(plan.calls, fn {id, name, args} ->
         Map.get_lazy(results, id, fn -> Durable.interrupted_result({id, name, args}) end)
       end)}
  end

  defp resume_tools(state, plan, _emit), do: {state, plan.messages}

  defp noop_emit(_event), do: :ok

  defp do_runtime_run(state, prompt, opts) do
    user_message = Message.user(prompt, opts[:images] || [])
    messages = state.messages ++ [user_message]
    {runtime_mod, _runtime_opts} = state.runtime

    Telemetry.span(:agent, %{agent: state.agent_module, session_id: state.id}, fn ->
      case runtime_mod.run(prompt, runtime_context(state), opts) do
        {:ok, result} ->
          {response, result_messages, assigns} = normalize_runtime_result(result, state.assigns)
          final_messages = messages ++ result_messages
          {{:ok, response}, final_messages, assigns}

        {:error, reason} ->
          {{:error, reason}, messages, state.assigns}
      end
    end)
  end

  defp runtime_context(state) do
    {_runtime_mod, runtime_opts} = state.runtime

    %{
      agent: state.pid,
      agent_module: state.agent_module,
      session_id: state.id,
      cwd: state.cwd,
      sandbox: state.sandbox,
      secrets: state.secrets,
      system_prompt: state.system_prompt,
      project_context: state.project_context,
      runtime_opts: runtime_opts,
      trace_context: TraceContext.current(),
      assigns: state.assigns,
      user_state: state.user_state
    }
  end

  defp normalize_runtime_result(response, assigns) when is_binary(response) do
    {response, [Message.assistant(response)], assigns}
  end

  defp normalize_runtime_result(%{} = result, assigns) do
    response = Map.get(result, :response) || Map.get(result, "response") || ""
    messages = Map.get(result, :messages) || Map.get(result, "messages") || [Message.assistant(response)]
    next_assigns = Map.get(result, :assigns) || Map.get(result, "assigns") || assigns

    {response, messages, next_assigns}
  end

  defp do_stream(%{runtime: {Native, _}} = state, prompt, opts, emit, abort_ref) do
    do_native_stream(state, prompt, opts, emit, abort_ref)
  end

  defp do_stream(state, _prompt, _opts, emit, _abort_ref) do
    {runtime_mod, _runtime_opts} = state.runtime
    reason = {:streaming_not_supported_by_runtime, runtime_mod}
    emit.({:error, reason})
    {:error, reason}
  end

  defp do_native_stream(state, prompt, opts, emit, abort_ref) do
    max_turns = opts[:max_turns] || @default_max_turns
    images = opts[:images] || []

    user_message = Message.user(prompt, images)
    messages = state.messages ++ [user_message]

    emit.(:agent_start)

    Telemetry.span(:agent, %{agent: state.agent_module, session_id: state.id}, fn ->
      result =
        case journal_start(state, user_message, max_turns) do
          :ok -> streaming_loop(state, messages, max_turns, 0, emit, abort_ref)
          {:error, reason} -> emit_stream_error(emit, reason)
        end

      emit.(:agent_end)
      result
    end)
  end

  defp agent_loop(state, messages, max_turns, turn) when turn >= max_turns do
    response = extract_text_response(messages)
    {:ok, messages, response, state.assigns}
  end

  defp agent_loop(state, messages, max_turns, turn) do
    with {:ok, messages} <- take_steering(state, messages),
         {:ok, compacted} <- compaction_checkpoint(state, messages),
         :ok <- journal_compaction(state, messages, compacted) do
      agent_turn(state, compacted, max_turns, turn)
    end
  end

  defp agent_turn(state, messages, max_turns, turn) do
    tools = build_req_llm_tools(state.tools, state)

    call = &ReqLLM.generate_text(state.llm.model, &1, llm_opts(state, tools))
    {result, messages} = llm_request(state, messages, turn, false, fn -> false end, call)

    # The response is stored before anything acts on it or shows it.
    with {:ok, response} <- result,
         :ok <- sync(state),
         assistant_message = Translate.response_to_message(response),
         :ok <- journal(state, [{:assistant, assistant_message}]) do
      record_compaction_usage(state, response, messages)
      messages = messages ++ [assistant_message]
      view_event = &GenServer.cast(state.pid, {:view_event, state.turn.abort_ref, &1})
      text = Message.text(assistant_message)
      if text != "", do: view_event.({:text, text})

      cond do
        Message.has_tool_calls?(assistant_message) ->
          state
          |> execute_tool_calls(assistant_message, messages, view_event)
          |> after_tool_round(state, &agent_loop(&1, &2, max_turns, turn + 1))

        continuation = yield_continuation(state, assistant_message, messages, turn, max_turns) ->
          agent_loop(state, messages ++ [continuation], max_turns, turn + 1)

        true ->
          response_text = Message.text(assistant_message)
          {:ok, messages, response_text, state.assigns}
      end
    end
  end

  # The user message an `on_yield` hook continues the run with, or nil when
  # the answer stands. On the run's last turn the answer stands without asking:
  # a continuation there would end the run on the answer the hook rejected,
  # with its message left unanswered in the history.
  defp yield_continuation(_state, _assistant_message, _messages, turn, max_turns) when turn + 1 >= max_turns, do: nil

  defp yield_continuation(%{hooks: []}, _assistant_message, _messages, _turn, _max_turns), do: nil

  defp yield_continuation(state, assistant_message, messages, turn, max_turns) do
    context =
      state
      |> tool_context([])
      |> Map.merge(%{messages: messages, turn: turn, max_turns: max_turns})

    # A hook that crashed leaves the answer standing.
    case supervise(fn -> Hooks.run_on_yield(state.hooks, assistant_message, context) end, :infinity, :stop) do
      {:ok, {:continue, text}} -> Message.user(text)
      _ -> nil
    end
  end

  defp streaming_loop(state, messages, max_turns, turn, _emit, _abort_ref) when turn >= max_turns do
    response = extract_text_response(messages)
    {:ok, messages, response, state.assigns}
  end

  defp streaming_loop(%{turn: %{abort_ref: abort_ref}} = state, messages, max_turns, turn, emit, abort_ref) do
    with {:ok, messages} <- take_steering(state, messages),
         {:ok, compacted} <- compaction_checkpoint(state, messages),
         :ok <- journal_compaction(state, messages, compacted) do
      emit.(:turn_start)
      stream_turn(state, compacted, max_turns, turn, emit, abort_ref)
    else
      {:error, reason} -> emit_stream_error(emit, reason)
    end
  end

  defp streaming_loop(_state, _messages, _max_turns, _turn, _emit, _abort_ref) do
    {:error, :aborted}
  end

  defp start_run(state, prompt, opts, from) do
    case prior_request(state, opts[:request_id]) do
      :resume ->
        start_resume(state, {:run, from}, opts)

      {:done, result} ->
        GenServer.reply(from, result)
        state

      :new ->
        parent = self()
        state = begin_durable_run(state, opts[:request_id])
        state = view_run_started(state, prompt, opts)
        state = %{state | turn: Turn.start(state.turn, {:run, from}, length(state.messages))}

        start_worker(state, opts, fn ->
          result = do_run(state, prompt, opts)
          GenServer.cast(parent, {:run_complete, state.turn.abort_ref, from, result})
        end)
    end
  end

  defp start_stream(state, prompt, opts, subscriber_ref) do
    case prior_request(state, opts[:request_id]) do
      :resume ->
        start_resume(state, {:stream, subscriber_ref}, opts)

      {:done, result} ->
        end_stream(state, subscriber_ref, outcome_event(result))

      :new ->
        state = begin_durable_run(state, opts[:request_id])
        state = view_run_started(state, prompt, opts)
        turn = Turn.start(state.turn, {:stream, subscriber_ref}, length(state.messages))
        state = %{state | turn: %{turn | input: opts[:input]}}
        start_stream_task(state, opts, subscriber_ref, &do_stream(&1, prompt, opts, &2, &3))
    end
  end

  defp start_stream_task(state, opts, subscriber_ref, run) do
    parent = self()
    abort_ref = state.turn.abort_ref

    start_worker(state, opts, fn ->
      result = run.(state, &broadcast_stream_event(parent, abort_ref, subscriber_ref, &1), abort_ref)
      GenServer.cast(parent, {:stream_complete, abort_ref, subscriber_ref, result})
    end)
  end

  # Each turn runs as a child of the turn supervisor. The session monitors it
  # too, to learn of a worker that dies without reporting how its run ended.
  # The native loop does not trap exits, so it stops at once; a custom runtime
  # that traps holds up the abort, and the session, only for `@worker_shutdown`.
  defp start_worker(state, opts, fun) do
    Sandbox.Lease.active(state.sandbox)
    trace_context = TraceContext.capture(opts)

    {:ok, worker} =
      Task.Supervisor.start_child(
        state.turn_supervisor,
        fn ->
          TraceContext.attach(trace_context)
          fun.()
        end,
        shutdown: @worker_shutdown
      )

    Process.monitor(worker)
    %{state | turn: %{state.turn | worker: worker}}
  end

  # A submission with a request id the session already knows: the run it
  # started was interrupted and continues, or it finished and its outcome is
  # returned without running again.
  defp prior_request(state, request_id) do
    if Durable.resumes?(state.durable, request_id) do
      :resume
    else
      case Durable.request_result(state.durable, request_id) do
        {:ok, result} -> {:done, result}
        :error -> :new
      end
    end
  end

  # The input the run started from is journaled with it, so it is settled
  # however the run ends, after a restart as well. One redelivered by an inbox
  # takes its place.
  defp start_resume(state, recipient, opts) do
    input = opts[:input] || state.durable.interrupted.input

    case Durable.resume(state.durable, &replay_safe_tool?(state, &1)) do
      {:give_up, durable, messages, reason} ->
        previous = state.messages
        settle_input(state, input, {:error, reason})
        state = persist_run(%{state | durable: durable, messages: messages}, {:error, reason})
        state |> view_history_changed(previous) |> answer(recipient, {:error, reason})

      {:ok, durable, plan, records} ->
        # Without the resume record the restart would go uncounted, so a run
        # that keeps crashing could never reach the limit. It stays interrupted.
        case Durable.append(state.session_store, session_store_opts(state), records) do
          :ok ->
            state = sync_queue(state)
            view_change(state, {:run_started, Enum.at(plan.messages, plan.prompt_index)})
            # What the interrupted run stored is history from here on, so a
            # resumed run that is aborted, like one that is abandoned, keeps it.
            turn = %{Turn.start(state.turn, recipient, plan.prompt_index) | input: input}
            state = %{state | durable: durable, turn: turn, messages: Durable.close(plan.messages)}
            start_resume_worker(state, recipient, opts, plan)

          # The run stays interrupted, and a later resume settles its own
          # input. A redelivered one is answered now, as its caller would be.
          {:error, reason} ->
            settle_input(state, opts[:input], {:error, reason})
            answer(state, recipient, {:error, reason})
        end
    end
  end

  defp start_resume_worker(state, {:run, from}, opts, plan) do
    parent = self()

    start_worker(state, opts, fn ->
      result = do_resume(state, plan)
      GenServer.cast(parent, {:run_complete, state.turn.abort_ref, from, result})
    end)
  end

  defp start_resume_worker(state, {:stream, ref}, opts, plan) do
    start_stream_task(state, opts, ref, &do_stream_resume(&1, plan, &2, &3))
  end

  defp answer(state, {:run, from}, result) do
    GenServer.reply(from, result)
    state
  end

  defp answer(state, {:stream, ref}, event), do: state |> broadcast(ref, event) |> broadcast(ref, :done)

  # Only the caller's own subscribers hear: no turn started.
  defp end_stream(state, subscriber_ref, event) do
    broadcast_subscribers(state, subscriber_ref, event)
    broadcast_subscribers(state, subscriber_ref, :done)
    state
  end

  defp outcome_event({:ok, answer}), do: {:text, answer}
  defp outcome_event({:error, reason}), do: {:error, reason}

  # A journaled run whose worker died is what a restart would find: the run
  # is read back from the store as interrupted, for the caller to resume or
  # give up, just as when the whole session process dies. Any other run ends
  # with the error. The input a journaled run started from is journaled too,
  # and is settled when the run is resumed, given up, or abandoned.
  defp worker_exited(state, error) do
    state = release_compaction_waiter(state, error)
    input = state.turn.input
    state = answer(state, state.turn.recipient, error)
    cancel_parked(state)
    state = state |> view_run_finished(run_error(error)) |> finish_turn()
    previous = state.messages

    state =
      if Durable.journaling?(state.durable) do
        reload_interrupted(state, input, error)
      else
        settle_input(state, input, error)
        if state.durable.current, do: persist_run(state, error), else: state
      end

    state |> view_history_changed(previous) |> maybe_start_queued_turn()
  end

  # An exit reason can carry anything the worker held, resolved secrets
  # included, and it reaches callers and notifiers, so it is reported as
  # redacted text.
  defp exit_summary(_state, reason) when is_atom(reason), do: reason
  defp exit_summary(state, reason), do: Secrets.redact_text(state.secrets, Exception.format_exit(reason))

  defp reload_interrupted(state, input, error) do
    store_opts = session_store_opts(state)
    snapshot = read_snapshot(state.session_store, store_opts)

    case Durable.load(state.session_store, store_opts, snapshot) do
      {:ok, reloaded, messages} ->
        # A worker that died before its start record was stored left no run
        # to resume with the input.
        if not match?(%{run_id: id} when id == state.durable.current.run_id, reloaded.interrupted),
          do: settle_input(state, input, error)

        %{state | durable: %{reloaded | restart_limit: state.durable.restart_limit}, messages: messages}

      {:error, reason} ->
        Logger.warning("failed to read the journal of a run whose worker exited: #{inspect(reason)}")
        settle_input(state, input, error)
        persist_run(state, error)
    end
  end

  defp broadcast_stream_event(parent, abort_ref, subscriber_ref, event) do
    GenServer.cast(parent, {:broadcast_event, abort_ref, event, subscriber_ref})
  end

  defp stream_turn(state, messages, max_turns, turn, emit, abort_ref) do
    tools = build_req_llm_tools(state.tools, state)

    emitted_counter = :counters.new(1, [:atomics])
    emitted? = fn -> :counters.get(emitted_counter, 1) > 0 end

    tracked_emit = fn event ->
      :counters.add(emitted_counter, 1, 1)
      emit.(event)
    end

    call = &run_stream_attempt(state.llm.model, &1, llm_opts(state, tools), tracked_emit)
    {result, messages} = llm_request(state, messages, turn, true, emitted?, call)

    with {:ok, response} <- result,
         :ok <- sync(state),
         assistant_message = Translate.response_to_message(response),
         :ok <- journal(state, [{:assistant, assistant_message}]) do
      handle_stream_response(state, response, assistant_message, messages, max_turns, turn, emit, abort_ref)
    else
      {:error, reason} ->
        emit_stream_error(emit, reason)
    end
  end

  defp handle_stream_response(state, response, assistant_message, messages, max_turns, turn, emit, abort_ref) do
    record_compaction_usage(state, response, messages)
    text = ReqLLM.Response.text(response) || ""
    messages = messages ++ [assistant_message]
    emit.(:turn_end)

    cond do
      Message.has_tool_calls?(assistant_message) ->
        state
        |> execute_tool_calls(assistant_message, messages, emit)
        |> after_tool_round(state, &streaming_loop(&1, &2, max_turns, turn + 1, emit, abort_ref))

      continuation = yield_continuation(state, assistant_message, messages, turn, max_turns) ->
        streaming_loop(state, messages ++ [continuation], max_turns, turn + 1, emit, abort_ref)

      true ->
        {:ok, messages, text, state.assigns}
    end
  end

  defp run_stream_attempt(model, context, llm_opts, tracked_emit) do
    with {:ok, stream_response} <- ReqLLM.stream_text(model, context, llm_opts) do
      ReqLLM.StreamResponse.process_stream(
        stream_response,
        on_result: fn chunk -> tracked_emit.({:text, chunk}) end,
        on_thinking: fn chunk -> tracked_emit.({:thinking, chunk}) end
      )
    end
  end

  defp emit_stream_error(emit, reason) do
    emit.({:error, reason})
    {:error, reason}
  end

  defp outbound_redactor(state) do
    [
      Secrets.redactor(state.secrets),
      state.redactor
    ]
    |> Enum.reject(&is_nil/1)
  end

  @doc false
  # Kept as a delegate: `Condukt.Session.message_to_req_llm/1` is called
  # directly by the test suite, and moving the implementation should not be a
  # breaking change for anyone who reached for it the same way.
  defdelegate message_to_req_llm(message), to: Translate

  defp llm_config(state) do
    [
      api_key: state.llm.api_key,
      base_url: state.llm.base_url,
      thinking_level: state.llm.thinking_level,
      max_tokens: state.llm.max_tokens,
      request_options: state.llm.request_options
    ]
  end

  defp llm_opts(state, tools) do
    trace_headers =
      TraceContext.current()
      |> TraceContext.child()
      |> TraceContext.headers(state.id)

    Translate.llm_opts(llm_config(state), tools, trace_headers)
  end

  defp attach_trace_context(opts) do
    case TraceContext.capture(opts) do
      nil -> Keyword.delete(opts, :trace_context)
      context -> Keyword.put(opts, :trace_context, context)
    end
  end

  defp build_req_llm_tools(tools, state) do
    Enum.map(tools, fn tool_spec ->
      spec = Tool.to_spec(tool_spec)

      ReqLLM.tool(
        name: spec.name,
        description: spec.description,
        parameter_schema: Translate.normalize_json_schema(spec.parameters),
        callback: fn args ->
          emit_secret_access(state, spec.name)
          context = tool_context(state, [])

          case Tool.execute(tool_spec, args, context) do
            {:ok, result, _assigns} when is_binary(result) ->
              Secrets.redact_text(state.secrets, result)

            {:ok, result, _assigns} ->
              JSON.encode!(Secrets.redact_result(state.secrets, result))

            {:ok, result} when is_binary(result) ->
              Secrets.redact_text(state.secrets, result)

            {:ok, result} ->
              JSON.encode!(Secrets.redact_result(state.secrets, result))

            {:error, reason} ->
              "Error: #{inspect(reason)}"

            {:park, call_state, _opts} ->
              # Nothing will wake the call, so undo what it started.
              Tool.cancel(tool_spec, call_state, context)
              "Error: #{spec.name} cannot wait for signals under this runtime"
          end
        end
      )
    end)
  end

  # One path for both callers. Each announces the calls before they run and
  # each result as it lands through its emitter: the streaming one to its
  # subscribers and notifier, the plain one to the view only.
  #
  # A call that parks leaves its round waiting: this worker blocks until the
  # session reports a woken call, runs it through `wake/3`, and repeats until
  # every call has a result. Aborting the turn terminates the worker, blocked
  # or not. Returns `{tool_results, messages, assigns_diff}`.
  defp execute_tool_calls(state, assistant_message, messages, emit) do
    tool_calls = Message.tool_calls(assistant_message)

    Enum.each(tool_calls, fn {id, name, args} -> emit.({:tool_call, name, id, args}) end)

    # Results are kept by position, not id, so each call keeps its own result
    # even if a provider repeats an id.
    calls = Enum.with_index(tool_calls)

    with {:ok, results} <- run_batches(state, tool_batches(state, calls), %{}, emit) do
      {tool_results, assigns_diff} =
        split_results_and_assigns(Enum.map(calls, fn {_call, index} -> Map.fetch!(results, index) end))

      {tool_results, messages, assigns_diff}
    end
  end

  # Consecutive calls of read-only tools form one batch and run together, as
  # do sub-agent calls whose role cannot change what a later call observes
  # (`Subagent.read_only_call?/2`); any other call is a batch of its own, so
  # calls that change the sandbox run one at a time, in call order. A batch
  # ends once each of its calls has a result, after waking from a park if it
  # parked.
  defp tool_batches(state, calls) do
    tool_map = build_tool_map(state.tools)

    Enum.chunk_by(calls, &batch_key(tool_map, &1))
  end

  # Unknown tools only answer with an error, so they change nothing.
  defp batch_key(tool_map, {{_id, name, args}, index}) do
    case Map.fetch(tool_map, name) do
      {:ok, {Subagent, opts}} -> if Subagent.read_only_call?(opts, args), do: :read, else: index
      {:ok, tool_spec} -> if Tool.read_only?(tool_spec), do: :read, else: index
      :error -> :read
    end
  end

  defp run_batches(_state, [], results, _emit), do: {:ok, results}

  defp run_batches(state, [batch | batches], results, emit) do
    results = Map.merge(results, run_tool_calls(state, batch, %{}, emit))

    with {:ok, results} <- await_tool_round(state, batch, results, emit) do
      run_batches(state, batches, results, emit)
    end
  end

  defp await_tool_round(state, calls, results, emit) do
    if Enum.all?(calls, fn {_call, index} -> Map.has_key?(results, index) end) do
      {:ok, results}
    else
      with {:ok, resumes} <- await_wakes(state) do
        woken = Enum.filter(calls, &woken?(&1, resumes, results))
        await_tool_round(state, calls, Map.merge(results, run_tool_calls(state, woken, resumes, emit)), emit)
      end
    end
  end

  defp woken?({{id, _name, _args}, index}, resumes, results),
    do: Map.has_key?(resumes, id) and not Map.has_key?(results, index)

  # Blocks this worker, which costs a process and nothing else, until the
  # session has a woken call for it. Aborting the turn terminates the worker;
  # the session going down ends the wait.
  defp await_wakes(state) do
    abort_ref = state.turn.abort_ref

    with {:ok, resumes} when map_size(resumes) == 0 <-
           GenServer.call(state.pid, {:take_ready, abort_ref}, :infinity) do
      monitor = Process.monitor(state.pid)

      receive do
        {:parking_ready, ^abort_ref} ->
          Process.demonitor(monitor, [:flush])
          await_wakes(state)

        {:DOWN, ^monitor, :process, _pid, _reason} ->
          {:error, :aborted}
      end
    end
  end

  # Runs `{call, index}` pairs, returning the outcomes of those that did not
  # park by index. `resumes` holds the `{event, state}` of woken calls by id.
  defp run_tool_calls(state, calls, resumes, emit) do
    tool_map = build_tool_map(state.tools)
    trace_context = TraceContext.current()

    calls
    |> Task.async_stream(
      fn {{id, name, _args} = tool_call, _index} ->
        TraceContext.attach(trace_context)
        resume = Map.get(resumes, id)

        outcome =
          case admit_tool_call(state, id, tool_map[name], resume) do
            :ok -> execute_tool_call(tool_map, tool_call, state, resume)
            {:error, :aborted} -> {Message.tool_result(id, {:error, :aborted}), %{}}
            {:error, reason} -> {Message.tool_result(id, {:error, not_recorded(name, reason)}), %{}}
          end

        if not match?({:parked, _id}, outcome) do
          journal_tool_result(state, outcome)
          woken_call_done(state, resumes, id)
        end

        outcome
      end,
      ordered: true,
      max_concurrency: tool_concurrency(state, calls),
      # Each call bounds its tool's own execution with the tool timeout, so a
      # hook waiting on a person is not cut off by it.
      timeout: :infinity
    )
    |> Enum.zip(calls)
    |> Enum.flat_map(fn
      {{:ok, {:parked, _id}}, _call} ->
        []

      {task_result, {{id, _name, _args}, index}} ->
        if match?({:exit, _reason}, task_result), do: woken_call_done(state, resumes, id)
        {result, _assigns} = outcome = task_result_to_tool_result(task_result, id, state)
        emit.({:tool_result, result.tool_call_id, Message.tool_result_content(result)})
        [{index, outcome}]
    end)
    |> Map.new()
  end

  # A woken call with a result is no longer one an abort cancels. Sent as soon
  # as each call finishes, not after its whole batch.
  defp woken_call_done(state, resumes, id) do
    if Map.has_key?(resumes, id), do: GenServer.cast(state.pid, {:parking_done, state.turn.abort_ref, [id]})
  end

  # Without hooks, one call per scheduler, as tools are mostly work. Hooks may
  # hold calls waiting on people rather than CPUs, so then every call in the
  # round runs at once, up to a cap that keeps one response from starting an
  # unbounded number of tools or sub-agents.
  defp tool_concurrency(%{hooks: []}, _calls), do: System.schedulers_online()

  defp tool_concurrency(_state, calls) do
    calls |> length() |> max(System.schedulers_online()) |> min(@max_hooked_tool_concurrency)
  end

  # The intent is stored before the tool runs, so a restarted session knows the
  # call may have taken effect, together with whether the tool was replay-safe
  # when it ran: a later build that declares it safe must not rerun a call made
  # while it was not. A call whose intent could not be stored does not run. A
  # woken parked call already stored its intent when it first ran.
  defp admit_tool_call(state, id, tool_spec, nil) do
    journal(state, [{:tool_intent, %{call_id: id, replay_safe: tool_spec != nil and Tool.replay_safe?(tool_spec)}}])
  end

  defp admit_tool_call(_state, _id, _tool_spec, _resume), do: :ok

  # Stored as soon as the call finishes, not when the round does, so a crash
  # while a slower call runs keeps this one's result. A result that fails to
  # store reads as interrupted on resume, which is the safe direction.
  defp journal_tool_result(state, {result, _assigns}), do: journal(state, [{:tool_result, result}])

  defp not_recorded(name, reason) do
    "#{name} was not run: the session could not record the call before running it (#{inspect(reason)})."
  end

  defp replay_safe_tool?(state, name) do
    case Map.fetch(build_tool_map(state.tools), name) do
      {:ok, tool_spec} -> Tool.replay_safe?(tool_spec)
      :error -> false
    end
  end

  defp after_tool_round({:error, reason}, _state, _continue), do: {:error, reason}

  defp after_tool_round({tool_results, messages, assigns_diff}, state, continue) do
    continue.(%{state | assigns: Map.merge(state.assigns, assigns_diff)}, messages ++ tool_results)
  end

  # A tool that never returns used to hang the turn forever, which a person at
  # a terminal can interrupt and a server-side run cannot. Bounded by the
  # session's own timeout, since a turn outliving it has nobody left to answer.
  defp tool_timeout(state), do: Map.get(state, :tool_timeout) || @default_timeout

  defp split_results_and_assigns(results_with_assigns) do
    Enum.reduce(results_with_assigns, {[], %{}}, fn {result, assigns}, {acc, merged} ->
      {[result | acc], Map.merge(merged, assigns)}
    end)
    |> then(fn {results, merged} -> {Enum.reverse(results), merged} end)
  end

  defp execute_tool_call(tool_map, {id, name, args} = call, state, resume) do
    metadata = %{
      tool: name,
      tool_call_id: id,
      args: args,
      session_id: state.id,
      agent: state.agent_module
    }

    {outcome, _args} =
      Telemetry.span(
        :tool_call,
        metadata,
        fn -> execute_hooked_tool(tool_map, call, state, resume) end,
        &tool_call_stop_metadata/1
      )

    outcome
  end

  # Returns the call's outcome with the arguments it ran with, for the
  # `:tool_call` stop event. `before_tool` runs once, before a fresh call;
  # `after_tool` runs on the result, after the last wake of a call that parked.
  # The result hooks see and replace is already redacted, and a replacement is
  # redacted again before the model sees it.
  defp execute_hooked_tool(tool_map, {_id, _name, args} = call, %{hooks: []} = state, resume) do
    {run_tool(tool_map, call, state, resume), args}
  end

  defp execute_hooked_tool(tool_map, {id, name, args}, state, nil = resume) do
    context = tool_context(state, [], id)
    hook_call = %{id: id, name: name, args: args}

    case supervise(fn -> Hooks.run_before_tool(state.hooks, hook_call, context) end, :infinity, :stop) do
      {:ok, {:ok, args}} ->
        outcome = run_tool(tool_map, {id, name, args}, state, resume)
        {after_tool(state, %{hook_call | args: args}, outcome, context), args}

      {:ok, {:block, reason}} ->
        reason = if is_binary(reason), do: reason, else: inspect(reason)
        blocked = {error_result(state, id, "Tool call blocked: " <> reason), %{}}
        {after_tool(state, hook_call, blocked, context), args}

      {:error, reason} ->
        blocked = {error_result(state, id, "Tool call blocked: " <> exit_message(reason)), %{}}
        {after_tool(state, hook_call, blocked, context), args}
    end
  end

  defp execute_hooked_tool(tool_map, {id, name, args} = call, state, resume) do
    context = tool_context(state, [], id)
    {after_tool(state, %{id: id, name: name, args: args}, run_tool(tool_map, call, state, resume), context), args}
  end

  defp after_tool(_state, _call, {:parked, _id} = parked, _context), do: parked

  defp after_tool(state, call, {message, assigns}, context) do
    result =
      case message.content do
        {:error, reason} -> {:error, reason}
        content -> {:ok, content}
      end

    message =
      case supervise(fn -> Hooks.run_after_tool(state.hooks, call, result, context) end, :infinity, :stop) do
        {:ok, ^result} -> message
        {:ok, {:ok, content}} -> %{message | content: Secrets.redact_result(state.secrets, content)}
        {:ok, {:error, _} = error} -> %{message | content: Secrets.redact_result(state.secrets, error)}
        {:error, reason} -> error_result(state, call.id, "after_tool hook failed: " <> exit_message(reason))
      end

    {message, assigns}
  end

  # The tool runs in its own process, bounded by the tool timeout. A tool that
  # must not stop halfway finishes when the turn is aborted, as
  # `Tool.on_abort/1` asks; any other dies with the turn.
  defp run_tool(tool_map, {id, name, _args} = call, state, resume) do
    on_exit =
      case Map.fetch(tool_map, name) do
        {:ok, spec} -> if Tool.on_abort(spec) == :finish, do: :finish, else: :stop
        :error -> :stop
      end

    case supervise(fn -> execute_tool(tool_map, call, state, resume) end, tool_timeout(state), on_exit) do
      {:ok, outcome} -> outcome
      {:error, :timeout} -> {Message.tool_result(id, {:error, :timeout}), %{}}
      {:error, reason} -> {error_result(state, id, exit_message(reason)), %{}}
    end
  end

  # Runs `fun` in a process linked to this one and waits for its result. The
  # link takes the process down with this one, as an abort takes the turn's
  # whole process tree, while trapping exits for the wait turns a crash in it
  # into `{:error, reason}`, failing only what it was doing. An exit this
  # process receives meanwhile is passed on to `fun`'s process and then
  # honored, at once or for `on_exit: :finish` once `fun` finishes, even when
  # it arrived just after the result. The process leaves by signal, as it
  # would without trapping, so a span around the wait does not report the
  # abort as an exception. Past `timeout`, the process is killed and the
  # result is `{:error, :timeout}`.
  defp supervise(fun, timeout, on_exit) do
    trapping? = Process.flag(:trap_exit, true)
    caller = self()
    ref = make_ref()
    trace_context = TraceContext.current()

    {:ok, pid} =
      Task.start_link(fn ->
        TraceContext.attach(trace_context)
        send(caller, {ref, fun.()})
      end)

    deadline = if timeout == :infinity, do: :infinity, else: System.monotonic_time(:millisecond) + timeout

    {result, exiting} = await_supervised(pid, ref, deadline, on_exit, trapping?, nil)
    Process.flag(:trap_exit, trapping?)
    exiting = exiting || (not trapping? && trapped_exit())
    if exiting, do: Process.exit(self(), exiting)
    result
  end

  defp await_supervised(pid, ref, deadline, on_exit, trapping?, exiting) do
    receive do
      {^ref, result} ->
        receive do: ({:EXIT, ^pid, _reason} -> :ok)
        {{:ok, result}, exiting}

      {:EXIT, ^pid, reason} ->
        {{:error, reason}, exiting}

      {:EXIT, _from, :normal} when not trapping? ->
        await_supervised(pid, ref, deadline, on_exit, trapping?, exiting)

      {:EXIT, _from, reason} when not trapping? and is_nil(exiting) ->
        Process.exit(pid, reason)

        if on_exit == :finish,
          do: await_supervised(pid, ref, :infinity, on_exit, trapping?, reason),
          else: {nil, reason}
    after
      remaining(deadline) ->
        Process.unlink(pid)
        Process.exit(pid, :kill)
        # An exit it sent before the unlink is not one from elsewhere.
        receive do: ({:EXIT, ^pid, _reason} -> :ok), after: (0 -> :ok)
        {{:error, :timeout}, exiting}
    end
  end

  # An exit that arrived while the wait was over but exits were still trapped.
  defp trapped_exit do
    receive do: ({:EXIT, _from, reason} when reason != :normal -> reason), after: (0 -> nil)
  end

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  # Text from hooks and exits is as untrusted as a tool's own result.
  defp error_result(state, id, text), do: Message.tool_result(id, Secrets.redact_result(state.secrets, {:error, text}))

  defp crash_reason({reason, [{_, _, _, _} | _]}), do: reason
  defp crash_reason(reason), do: reason

  # The model sees this text, so stack traces are dropped.
  defp exit_message({exception, _stacktrace}) when is_exception(exception), do: Exception.message(exception)
  defp exit_message({reason, [{_, _, _, _} | _]}), do: exit_message(reason)
  defp exit_message(reason), do: inspect(reason)

  defp tool_call_stop_metadata({{:parked, _id}, args}), do: %{status: :parked, result: nil, args: args}

  defp tool_call_stop_metadata({{%Message{content: {:error, _} = error}, _assigns}, args}),
    do: %{status: :error, result: error, args: args}

  defp tool_call_stop_metadata({{%Message{content: content}, _assigns}, args}),
    do: %{status: :ok, result: content, args: args}

  defp llm_turn_metadata(state, messages, turn, streaming?) do
    %{
      agent: state.agent_module,
      session_id: state.id,
      model: Translate.model_identifier(state.llm.model),
      turn: turn,
      streaming?: streaming?,
      messages: messages,
      tool_count: length(state.tools)
    }
  end

  defp llm_turn_stop_metadata({:ok, response}) do
    %{
      status: :ok,
      assistant_message: Translate.response_to_message(response),
      usage: Map.get(response, :usage),
      finish_reason: Map.get(response, :finish_reason)
    }
  end

  defp llm_turn_stop_metadata({:error, reason}) do
    %{status: :error, error: reason}
  end

  defp task_result_to_tool_result({:ok, outcome}, _id, _state), do: outcome

  defp task_result_to_tool_result({:exit, reason}, id, state), do: {error_result(state, id, exit_message(reason)), %{}}

  defp execute_tool(tool_map, {id, name, _args} = call, state, resume) do
    case Map.fetch(tool_map, name) do
      :error ->
        {Message.tool_result(id, {:error, "Unknown tool: #{name}"}), %{}}

      {:ok, tool_spec} ->
        emit_secret_access(state, name, id)
        # A tool that must not stop halfway traps exits, so an abort reaches it
        # as an `{:EXIT, _, _}` message instead of killing it.
        if Tool.on_abort(tool_spec) == :finish, do: Process.flag(:trap_exit, true)
        execute_known_tool(tool_spec, call, state, resume)
    end
  end

  defp emit_secret_resolve(session_id, agent_module, secrets) do
    case Secrets.names(secrets) do
      [] ->
        :ok

      names ->
        Telemetry.emit(
          [:secrets, :resolve],
          %{count: length(names)},
          %{session_id: session_id, agent: agent_module, names: names}
        )
    end
  end

  defp emit_secret_access(state, tool, tool_call_id \\ nil) do
    case Secrets.names(state.secrets) do
      [] ->
        :ok

      names ->
        metadata =
          %{session_id: state.id, agent: state.agent_module, tool: tool, names: names}
          |> maybe_put(:tool_call_id, tool_call_id)

        Telemetry.emit([:secrets, :access], %{count: length(names)}, metadata)
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp execute_known_tool({module, opts}, {id, _name, _args} = call, state, resume) do
    execute_tool_spec({module, opts}, call, tool_context(state, opts, id), resume)
  end

  defp execute_known_tool(tool_spec, {id, _name, _args} = call, state, resume) do
    execute_tool_spec(tool_spec, call, tool_context(state, [], id), resume)
  end

  defp tool_context(state, opts, tool_call_id \\ nil) do
    %{
      session_id: state.id,
      tool_call_id: tool_call_id,
      # Identify the turn making the call, for work it starts that must not
      # outlive it, and whether that turn streams events.
      turn_ref: state.turn.abort_ref,
      stream?: match?({:stream, _}, state.turn.recipient),
      agent: state.pid,
      agent_module: state.agent_module,
      # A tool bound to another sandbox, as `{Bash, sandbox: mac}`, uses it.
      sandbox: tool_sandbox(opts) || state.sandbox,
      cwd: state.cwd,
      opts: opts,
      secrets: state.secrets,
      subagents: state.subagents,
      subagent_supervisor: state.subagent_supervisor,
      model: state.llm.model,
      thinking_level: state.llm.thinking_level,
      max_tokens: state.llm.max_tokens,
      api_key: state.llm.api_key,
      base_url: state.llm.base_url,
      llm_request_options: state.llm.request_options,
      trace_context: TraceContext.current(),
      assigns: state.assigns
    }
  end

  defp tool_sandbox(opts) when is_list(opts) do
    case Keyword.get(opts, :sandbox) do
      %Sandbox{} = sandbox -> sandbox
      _other -> nil
    end
  end

  defp tool_sandbox(_opts), do: nil

  defp tool_opts({_module, opts}), do: opts
  defp tool_opts(_tool_spec), do: []

  # A fresh call runs `call/2`; a woken one, `wake/3` with its event and state.
  defp execute_tool_spec(tool_spec, {id, _name, args} = call, context, resume) do
    outcome =
      case resume do
        nil -> Tool.execute(tool_spec, args, context)
        {event, call_state} -> Tool.wake(tool_spec, event, call_state, context)
      end

    case outcome do
      {:ok, result, assigns} when is_map(assigns) ->
        {Message.tool_result(id, Secrets.redact_result(context[:secrets], result)), assigns}

      {:ok, result} ->
        {Message.tool_result(id, Secrets.redact_result(context[:secrets], result)), %{}}

      {:error, reason} ->
        {Message.tool_result(id, Secrets.redact_result(context[:secrets], {:error, reason})), %{}}

      {:park, call_state, opts} ->
        park_tool_call(tool_spec, call, context, call_state, opts)
    end
  end

  # Where a tool call's `{:park, state, opts}` parks it: the session records
  # the park, and the turn's worker waits until `wake/3` handles its event.
  defp park_tool_call(tool_spec, {id, name, _args}, context, call_state, opts) do
    case request_park(tool_spec, {id, name}, context, call_state, opts) do
      :ok ->
        {:parked, id}

      {:error, :aborted} ->
        # The abort refused this park, so nothing else cancels what the call started.
        Tool.cancel(tool_spec, call_state, context)
        {Message.tool_result(id, {:error, :aborted}), %{}}

      {:error, reason} ->
        {Message.tool_result(id, {:error, {:invalid_park, reason}}), %{}}
    end
  end

  defp request_park(tool_spec, call, context, call_state, opts) do
    with :ok <- if(Tool.wakes?(tool_spec), do: :ok, else: {:error, :no_wake_callback}),
         {:ok, park} <- Park.new(opts) do
      GenServer.call(context.agent, {:park, context.turn_ref, call, call_state, park}, :infinity)
    end
  end

  defp build_tool_map(tools) do
    tools
    |> Map.new(fn
      %Inline{} = inline -> {inline.name, inline}
      {module, opts} = spec -> {Tool.name(spec), {module, opts}}
      module -> {Tool.name(module), module}
    end)
  end

  defp extract_text_response(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find(&(&1.role == :assistant))
    |> case do
      nil -> ""
      msg -> Message.text(msg)
    end
  end

  # Sends an event to its subscribers here and hands it to the view process,
  # which publishes it and records it. A session built without one, as a few
  # tests do, publishes it itself.
  defp broadcast(state, ref, event) do
    broadcast_subscribers(state, ref, event)
    publish(state, event)
  end

  # Past the caller's own subscribers: through the viewer when there is one,
  # which records the event and publishes it to the notifier.
  defp publish(state, event) do
    case state.viewer do
      nil -> Notifier.publish(state.notifier, state.id, event)
      viewer -> GenServer.cast(viewer, {:event, event})
    end

    state
  end

  defp broadcast_subscribers(state, ref, event) do
    for pid <- Turn.listeners(state.turn, ref) do
      send(pid, {ref, event})
    end
  end

  defp maybe_dispatch_event(state, event) do
    case state.agent_module.handle_event(event, state.user_state) do
      {:noreply, user_state} ->
        %{state | user_state: user_state}

      {:stop, _reason, user_state} ->
        %{state | user_state: user_state} |> abort_turn() |> maybe_start_queued_turn()
    end
  end

  defp restore_value(opts, key, stored_value) do
    explicit_keys = Keyword.get(opts, :explicit_keys, MapSet.new())

    cond do
      MapSet.member?(explicit_keys, key) ->
        Keyword.fetch!(opts, key)

      is_nil(stored_value) ->
        Keyword.get(opts, key)

      true ->
        stored_value
    end
  end

  defp restore_messages(state, nil), do: state
  defp restore_messages(state, %Snapshot{messages: messages}), do: %{state | messages: messages}

  # Read before the session starts, so a journal that cannot be read fails the
  # start rather than starting a session that would reuse its run ids.
  defp load_durable(opts, snapshot) do
    case opts[:session_store] do
      nil ->
        {:ok, nil}

      store ->
        case Durable.load(store, session_store_opts(opts), snapshot) do
          {:ok, durable, messages} ->
            {:ok, {%{durable | restart_limit: opts[:restart_limit] || Durable.default_restart_limit()}, messages}}

          {:error, reason} ->
            {:error, {:journal_load_failed, reason}}
        end
    end
  end

  # The journal is read but never acted on here: an interrupted run waits for
  # the caller to resume it.
  defp restore_durable(state, nil), do: state

  defp restore_durable(state, {durable, messages}) do
    if durable.interrupted do
      Logger.info("session #{state.id} has an interrupted run; Condukt.Session.resume/2 continues it")
    end

    %{state | durable: durable, messages: messages}
  end

  defp journaled?(state), do: state.durable.enabled and match?({Native, _}, state.runtime)

  # A new run while an earlier one is interrupted closes that one first, so
  # what it stored stays in the history and its request id cannot run again.
  defp begin_durable_run(state, request_id) do
    state =
      if state.durable.interrupted do
        previous = state.messages
        {durable, messages, outcome} = Durable.abandon(state.durable)
        settle_input(state, state.durable.interrupted.input, outcome)
        state = persist_run(%{state | durable: durable, messages: messages}, outcome)
        view_history_changed(state, previous)
      else
        state
      end

    # A run without a journal still gets an id when it carries a request id,
    # so its outcome is remembered for retries.
    if journaled?(state) or request_id,
      do: %{state | durable: Durable.begin_run(state.durable, request_id, journaled?(state))},
      else: state
  end

  # Saves the snapshot a finished run leaves, then drops the journal it no
  # longer needs. A journal whose snapshot failed to save is kept, so a restart
  # still finds the run, and its end record says the run is over and how.
  defp persist_run(state, result) do
    journaled? = Durable.journaling?(state.durable)
    result = stored_outcome(state, result)
    if journaled?, do: append_to_journal(state, [{:run_end, result}])
    state = %{state | durable: Durable.finish_run(state.durable, result)}

    if persist_snapshot(state) == :ok and journaled? do
      Durable.clear(state.session_store, session_store_opts(state))
    end

    state
  end

  # How a run ended, as the journal and the snapshot keep it: an answer's text,
  # or an error that is an atom or else its description. A raw reason can hold
  # structs a freshly started VM cannot decode yet, which would cost the whole
  # record, and, for a provider error, a copy of the conversation it sent.
  defp stored_outcome(_state, {:ok, text}) when is_binary(text), do: {:ok, text}
  defp stored_outcome(state, {:ok, other}), do: {:ok, describe(state, other)}
  defp stored_outcome(_state, {:error, reason}) when is_atom(reason), do: {:error, reason}
  defp stored_outcome(state, {:error, reason}), do: {:error, describe(state, reason)}

  defp describe(state, term) do
    text = if is_exception(term), do: Exception.message(term), else: inspect(term, limit: 20, printable_limit: 1_000)
    Secrets.redact_text(state.secrets, text)
  end

  # The history the run starts from is fingerprinted, so a restart does not
  # replay a journal left behind by another history onto this one. The input
  # the run answers is kept with it, so a restart still settles it.
  defp journal_start(%{durable: %{current: %{journaled: true, request_id: request_id}}} = state, message, max_turns) do
    start = %{
      message: message,
      request_id: request_id,
      input: state.turn.input,
      max_turns: max_turns,
      base: Durable.fingerprint(state.messages)
    }

    journal(state, [{:run_start, start}])
  end

  defp journal_start(_state, _message, _max_turns), do: :ok

  # A compactor without a background policy runs again over the whole history
  # at every checkpoint, deterministically, so a resume recomputes its result
  # rather than the journal storing the whole history every round.
  defp journal_compaction(%{compaction: %{policy: nil}}, _messages, _compacted), do: :ok
  defp journal_compaction(_state, messages, messages), do: :ok
  defp journal_compaction(state, _messages, compacted), do: journal(state, [{:messages, compacted}])

  # From the worker, through the session process, which fences a superseded
  # turn's records.
  defp journal(%{durable: %{current: %{journaled: true}}} = state, records) do
    GenServer.call(state.pid, {:journal, state.turn.abort_ref, records}, :infinity)
  end

  defp journal(_state, _records), do: :ok

  defp append_to_journal(%{durable: %{current: %{journaled: true, run_id: run_id}}} = state, records) do
    records = Enum.map(records, fn {kind, payload} -> {kind, run_id, payload} end)
    Durable.append(state.session_store, session_store_opts(state), records)
  end

  defp append_to_journal(_state, _records), do: :ok

  defp journal_input(_state, []), do: :ok
  defp journal_input(state, steering), do: append_to_journal(state, [{:input, steering}])

  # A store that keeps a journal is the session's durable record, so one that
  # cannot be read must not start the session over: the next save would
  # replace the stored history with an empty one. A snapshot-only store is a
  # cache, and a session without it starts fresh.
  defp load_snapshot(nil, _opts), do: {:ok, nil}

  defp load_snapshot(session_store, opts) do
    store_opts = session_store_opts(opts)

    if SessionStore.journal?(session_store) do
      case SessionStore.load(session_store, store_opts) do
        {:ok, loaded} -> migrate_durable_snapshot(loaded)
        :not_found -> {:ok, nil}
        {:error, reason} -> {:error, {:snapshot_load_failed, reason}}
      end
    else
      {:ok, read_snapshot(session_store, store_opts)}
    end
  end

  # A snapshot from a newer Condukt, as after a rollback, is refused for the
  # same reason: starting without it would save over it.
  defp migrate_durable_snapshot(loaded) do
    case Snapshot.migrate(loaded) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, reason} -> {:error, {:snapshot_load_failed, reason}}
    end
  end

  defp read_snapshot(session_store, store_opts) do
    case SessionStore.load(session_store, store_opts) do
      {:ok, loaded} ->
        migrate_snapshot(loaded)

      :not_found ->
        nil

      {:error, reason} ->
        Logger.warning("failed to load session snapshot: #{inspect(reason)}")
        nil
    end
  end

  # Every store hands its term through the same migration, so a snapshot
  # written by an older build is read the same way whether it came off disk or
  # out of a table.
  defp migrate_snapshot(loaded) do
    case Snapshot.migrate(loaded) do
      {:ok, snapshot} ->
        snapshot

      {:error, reason} ->
        Logger.warning("ignoring unreadable session snapshot: #{inspect(reason)}")
        nil
    end
  end

  defp persist_or_clear_snapshot(%__MODULE__{session_store: nil}, _mode), do: :ok

  defp persist_or_clear_snapshot(state, :clear) do
    case SessionStore.clear(state.session_store, session_store_opts(state)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to clear session snapshot: #{inspect(reason)}")
        :ok
    end
  end

  defp persist_snapshot(%__MODULE__{session_store: nil}), do: :ok

  defp persist_snapshot(state) do
    snapshot =
      Snapshot.new(%{
        id: state.id,
        actor: state.actor,
        messages: state.messages,
        model: state.llm.model,
        thinking_level: state.llm.thinking_level,
        system_prompt: state.configured_system_prompt,
        created_at: state.created_at
      })
      |> Snapshot.put_runs(state.durable.last_run_id, state.durable.requests)

    case SessionStore.save(state.session_store, snapshot, session_store_opts(state)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to persist session snapshot: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp session_store_opts(opts) when is_list(opts) do
    store_opts = Keyword.get(opts, :session_store_opts, []) || []

    store_opts
    |> Keyword.put(:agent_module, Keyword.get(opts, :agent_module))
    |> Keyword.put(:cwd, Keyword.get(opts, :cwd))
    |> maybe_put_store_id(Keyword.get(opts, :id), Keyword.has_key?(opts, :id))
    |> maybe_put_store_key(Keyword.get(opts, :session_store_key))
  end

  defp session_store_opts(%__MODULE__{session_store_opts: opts}) when is_list(opts), do: opts

  defp session_store_opts(%__MODULE__{} = state) do
    [
      agent_module: state.agent_module,
      cwd: state.cwd
    ]
  end

  defp maybe_put_store_id(opts, id, true), do: Keyword.put(opts, :id, id)
  defp maybe_put_store_id(opts, _id, false), do: opts

  defp maybe_put_store_key(opts, nil), do: opts
  defp maybe_put_store_key(opts, key), do: Keyword.put(opts, :key, key)

  defp maybe_compact(%{compaction: %{spec: nil}} = state), do: state

  defp maybe_compact(%{compaction: %{policy: nil}} = state) do
    %{state | messages: Compaction.apply(state.compaction.spec, state.messages, compaction_metadata(state))}
  end

  defp maybe_compact(state) do
    {compaction, messages, _error} = Compaction.take_result(state.compaction, state.messages)
    compaction = Compaction.background(compaction, messages, compaction_overhead(state), compaction_metadata(state))
    %{state | messages: messages, compaction: compaction}
  end

  defp compaction_checkpoint(state, messages, phase \\ :background)

  defp compaction_checkpoint(%{compaction: %{policy: nil}} = state, messages, phase) do
    opts = Compaction.compactor_opts(phase)
    {:ok, Compaction.apply(state.compaction.spec, messages, compaction_metadata(state), opts)}
  end

  defp compaction_checkpoint(state, messages, phase) do
    GenServer.call(
      state.pid,
      {:compaction_checkpoint, state.turn.abort_ref, messages, TraceContext.current(), phase},
      :infinity
    )
  end

  # Sends one model request with transient retries and returns the result with
  # the messages it used. Token estimates can admit a request the provider
  # rejects as too long, so that rejection is compacted and retried once.
  defp llm_request(state, messages, turn, streaming?, emitted?, call) do
    result = llm_attempts(state, messages, turn, streaming?, emitted?, call)

    with {:error, reason} <- result,
         true <- not is_nil(state.compaction.spec) and not emitted?.() and Retry.context_overflow?(reason),
         {:ok, compacted} when compacted != messages <- compaction_checkpoint(state, messages, :overflow),
         :ok <- journal_compaction(state, messages, compacted) do
      Logger.warning("provider rejected the request as too long; retrying once after compaction")
      {llm_attempts(state, compacted, turn, streaming?, emitted?, call), compacted}
    else
      {:error, :aborted} = aborted -> {aborted, messages}
      _no_retry -> {result, messages}
    end
  end

  defp llm_attempts(state, messages, turn, streaming?, emitted?, call) do
    context = Translate.context(messages, outbound_redactor(state), state.system_prompt)

    attempt = fn ->
      :ok = sync(state)
      call.(context)
    end

    Telemetry.span(
      :llm_turn,
      llm_turn_metadata(state, messages, turn, streaming?),
      fn -> Retry.with_retry(state.llm.retry, emitted?, attempt) end,
      &llm_turn_stop_metadata/1
    )
  end

  defp record_compaction_usage(%{compaction: %{policy: nil}}, _response, _messages), do: :ok

  defp record_compaction_usage(state, response, messages) do
    # Send only the accounting, not the stream or other provider resources.
    GenServer.cast(state.pid, {:compaction_usage, state.turn.abort_ref, %{usage: response.usage}, messages})
  end

  defp compaction_checkpoint_reply(state, from, overhead, metadata, phase) do
    protected_count = if state.turn.prompt_index, do: length(state.messages) - state.turn.prompt_index, else: 1

    case Compaction.checkpoint(state.compaction, state.messages, overhead, from, metadata, phase, protected_count) do
      {:continue, compaction, messages} ->
        state = put_compacted_messages(state, compaction, messages)
        {:reply, if(phase == :manual, do: :ok, else: {:ok, messages}), state}

      {:wait, compaction, messages} ->
        {:noreply, put_compacted_messages(state, compaction, messages)}

      {:error, reason, compaction, messages} ->
        {:reply, {:error, {:compaction_failed, reason}}, put_compacted_messages(state, compaction, messages)}
    end
  end

  defp compaction_finished(%{compaction: %{waiter: {from, overhead, metadata, phase}}} = state) do
    state = %{state | compaction: %{state.compaction | waiter: nil}}

    case compaction_checkpoint_reply(state, from, overhead, metadata, phase) do
      {:reply, result, state} ->
        GenServer.reply(from, result)
        {:noreply, maybe_start_queued_turn(state)}

      {:noreply, state} ->
        {:noreply, state}
    end
  end

  defp compaction_finished(%{turn: %{streaming: false}} = state) do
    {compaction, messages, _error} = Compaction.take_result(state.compaction, state.messages)
    {:noreply, put_compacted_messages(state, compaction, messages)}
  end

  defp compaction_finished(state), do: {:noreply, state}

  defp put_compacted_messages(state, compaction, messages) do
    turn =
      if state.turn.prompt_index do
        %{state.turn | prompt_index: state.turn.prompt_index + length(messages) - length(state.messages)}
      else
        state.turn
      end

    updated = %{state | compaction: compaction, messages: messages, turn: turn}

    cond do
      messages == state.messages ->
        updated

      # The turn's own history replaces the view's when it ends. A journaled
      # run records the compaction itself; a snapshot saved now would hold part
      # of the run that the journal replays on top of it.
      updated.turn.streaming ->
        if not Durable.journaling?(updated.durable), do: persist_snapshot(updated)
        %{updated | turn: Turn.rewrite_history(updated.turn)}

      # A background compaction that finishes while a run is interrupted is
      # dropped, as `compact/1` refuses one: the run's journal follows the
      # history it started from.
      updated.durable.interrupted ->
        %{state | compaction: compaction}

      true ->
        persist_snapshot(updated)
        view_history_changed(updated, state.messages)
    end
  end

  defp release_compaction_waiter(%{compaction: %{waiter: nil}} = state, _result), do: state

  defp release_compaction_waiter(%{compaction: %{waiter: {from, _, _, _}}} = state, result) do
    GenServer.reply(from, result)
    %{state | compaction: %{state.compaction | waiter: nil}}
  end

  defp abort_turn(state) do
    state = release_compaction_waiter(state, {:error, :aborted})
    # The worker does not trap exits, so it is gone when this returns. Its tool
    # calls are linked to it and go down with it, and so does what they own,
    # such as a foreground sub-agent's session and that session's own turn.
    if state.turn.worker, do: Task.Supervisor.terminate_child(state.turn_supervisor, state.turn.worker)

    state =
      case state.turn.recipient do
        {:run, from} ->
          GenServer.reply(from, {:error, :aborted})
          state

        {:stream, ref} ->
          state |> broadcast(ref, {:error, :aborted}) |> broadcast(ref, :done)

        nil ->
          state
      end

    cancel_parked(state)
    settle_inputs(state, :aborted)

    # Pending callers never started, so only they hear, not the notifier.
    Enum.each(state.turn.pending, fn
      {_prompt, _opts, {:run, from}} ->
        GenServer.reply(from, {:error, :aborted})

      {_prompt, _opts, {:stream, ref}} ->
        broadcast_subscribers(state, ref, {:error, :aborted})
        broadcast_subscribers(state, ref, :done)
    end)

    state = if state.turn.streaming, do: view_run_finished(state, :aborted), else: state
    Sandbox.Lease.idle(state.sandbox)
    state = end_parking(state)
    state = %{state | turn: Turn.abort(state.turn)}
    if state.durable.current, do: persist_run(state, {:error, :aborted}), else: state
  end

  # Starts the next queued input when the session is idle. A pending caller
  # gets the turn it asked for. Nobody waits on a turn started from a queued
  # message, so it streams to the notifier and the agent's `handle_event/2`
  # only. Other runtimes cannot stream, so input queued for them keeps
  # waiting, as before. Either way the view's queue follows what is left.
  defp maybe_start_queued_turn(state), do: state |> start_queued_turn() |> sync_queue()

  defp start_queued_turn(%{runtime: {Native, _}} = state)
       when not state.turn.streaming and is_nil(state.compaction.waiter) do
    case Turn.next_input(state.turn) do
      {nil, _turn} ->
        state

      # A request id already answered starts nothing, so the next input goes.
      {{prompt, opts, {:run, from}}, turn} ->
        %{state | turn: turn} |> start_run(prompt, opts, from) |> start_queued_turn()

      {{prompt, opts, {:stream, ref}}, turn} ->
        %{state | turn: turn} |> start_stream(prompt, opts, ref) |> start_queued_turn()

      {{:input, input, message}, turn} ->
        start_queued_input(%{state | turn: turn}, input, message)

      {%Message{} = message, turn} ->
        state = start_stream(%{state | turn: turn}, message.content, [images: message.images], make_ref())
        %{state | turn: %{state.turn | queued: true}}
    end
  end

  defp start_queued_turn(state), do: state

  # The input travels with the turn, so a durable journal records which
  # submission the turn answers and who hears how it ends. An input
  # redelivered after its run finished is settled with the stored outcome
  # instead of running again, and one whose interrupted run could not be
  # resumed was settled by the attempt, so the next input goes.
  defp start_queued_input(state, input, message) do
    case prior_request(state, input.request_id) do
      {:done, result} ->
        settle_input(state, input, settled(result))
        start_queued_turn(state)

      _new_or_resume ->
        state = start_stream(state, message.content, [request_id: input.request_id, input: input], make_ref())

        if state.turn.streaming,
          do: %{state | turn: %{state.turn | queued: true}},
          else: start_queued_turn(state)
    end
  end

  # Records the session under its parent in the session tree, which drops it
  # when this process exits, and has it take the input its inbox stored while
  # it was not running once it has started.
  defp join_sessions(state, parent) do
    :ok = Condukt.Sessions.join_parent(parent)
    if state.inbox, do: send(self(), {Condukt.Sessions, :drain})
    :ok
  end

  defp take_input(input, turn) do
    case Turn.submit(turn, input, Message.user(input.text)) do
      {:ok, turn} -> turn
      {:error, :duplicate} -> turn
    end
  end

  # Settles the input the running turn started from, and with `settle_inputs/2`
  # the queued ones an abort withdraws. Telling the sender calls another
  # session, possibly on another node, so it runs in its own process.
  defp settle_input(_state, nil, _outcome), do: :ok
  defp settle_input(_state, %{from: nil}, _outcome), do: :ok

  defp settle_input(state, input, outcome) do
    {:ok, _pid} = Task.start(Condukt.Sessions, :settle, [input, outcome, state.inbox])
    :ok
  end

  # An aborted run is stored as an error, but its input settles as `:aborted`,
  # as it does when the abort happens live.
  defp settled({:error, :aborted}), do: :aborted
  defp settled(result), do: result

  defp settle_inputs(state, outcome) do
    if state.turn.streaming, do: settle_input(state, state.turn.input, outcome)
    Enum.each(state.turn.inputs, fn {input, _message} -> settle_input(state, input, outcome) end)
  end

  # ============================================================================
  # View
  # ============================================================================

  # Starts the process that holds the view, linked so that neither outlives
  # the other's crash. It redacts what the session sends it, as it arrives.
  defp start_viewer(state) do
    {runtime, _opts} = state.runtime

    agent = %{
      module: state.agent_module,
      model: model_name(state.llm.model),
      thinking_level: state.llm.thinking_level,
      tools: Enum.map(state.tools, &Tool.name/1),
      runtime: runtime
    }

    {:ok, viewer} =
      Viewer.start_link(
        id: state.id,
        agent: agent,
        messages: state.messages,
        redactor: outbound_redactor(state),
        notifier: state.notifier
      )

    %{state | viewer: viewer}
  end

  # Only the name: a model spec can carry provider options a viewer must not see.
  defp model_name(model) when is_binary(model), do: model
  defp model_name(%{provider: provider, id: id}), do: "#{provider}:#{id}"
  defp model_name(_model), do: nil

  # Replies once the view process has handled what the session sent it
  # before, so the events an abort published have reached the notifier when
  # the call returns, as when the session published them itself. Callers such
  # as the background sub-agent manager read their notifier right after.
  defp reply_after_view(%{viewer: nil} = state, _from, reply), do: {:reply, reply, state}

  defp reply_after_view(state, from, reply) do
    GenServer.cast(state.viewer, {:reply, from, reply})
    {:noreply, state}
  end

  # Changes leave unredacted and in the session's order; the view process
  # redacts and numbers them. A session built without one sends nothing.
  defp view_change(%{viewer: nil}, _change), do: :ok
  defp view_change(state, change), do: GenServer.cast(state.viewer, {:change, change})

  # Sent whenever the queue may have changed; the view process drops it when
  # it did not.
  defp sync_queue(state) do
    view_change(state, {:queue, View.queue(state.turn)})
    state
  end

  defp view_run_started(state, prompt, opts) do
    state = sync_queue(state)
    view_change(state, {:run_started, Message.user(prompt, opts[:images] || [])})
    state
  end

  # Ends the view's run with what the turn added to the history, the
  # messages from `prompt_index` on, so a turn costs the view what it added.
  # Call it before the turn is finished or aborted, while `prompt_index` still
  # holds. History a compaction rewrote during the turn is replaced instead.
  defp view_run_finished(%{viewer: nil} = state, _error), do: state

  defp view_run_finished(%{turn: %{history_rewritten: true}} = state, error) do
    view_change(state, {:run_finished, error, []})
    view_change(state, {:messages, :replace, state.messages})
    state
  end

  defp view_run_finished(state, error) do
    view_change(state, {:run_finished, error, Enum.drop(state.messages, state.turn.prompt_index)})
    state
  end

  # Takes the history a turn ended with. A compactor without a background
  # policy compacts inside the turn's worker, where the session cannot see
  # it, so only then is the history compared with the one the turn started
  # from; anywhere else a rewrite goes through the session and is recorded.
  defp adopt_turn_messages(state, messages, assigns) do
    legacy? = state.compaction.policy == nil and state.compaction.spec != nil
    rewritten? = legacy? and not List.starts_with?(messages, state.messages)
    turn = if rewritten?, do: Turn.rewrite_history(state.turn), else: state.turn
    %{state | messages: messages, assigns: assigns, turn: turn}
  end

  # Replaces the view's history after an idle compaction changed it.
  defp view_history_changed(state, previous) do
    if state.messages != previous, do: view_change(state, {:messages, :replace, state.messages})
    state
  end

  defp run_error({:error, reason}), do: reason
  defp run_error(_result), do: nil

  # The one place a turn's parking changes. A durable journal stores `records`
  # here before they apply, as `Condukt.Session.Parking` describes.
  defp commit_parking(state, records) do
    parking = Enum.reduce(records, parking(state), &Parking.apply_record(&2, &1))
    if parking.timer, do: Process.cancel_timer(parking.timer)

    timer =
      case Parking.next_deadline(parking) do
        nil ->
          nil

        until ->
          delay = (until - System.os_time(:millisecond)) |> max(0) |> min(@max_timer)
          Process.send_after(self(), {:park_deadline, state.turn.abort_ref}, delay)
      end

    notify_worker(put_parking(state, %{parking | timer: timer}))
  end

  # Wakes the turn's worker when it is blocked on its parked round and a call
  # is ready for it.
  defp notify_worker(%{turn: %{worker: worker, parking: %Parking{blocked: true} = parking}} = state)
       when is_pid(worker) do
    if Parking.ready?(parking) do
      send(worker, {:parking_ready, state.turn.abort_ref})
      put_parking(state, %{parking | blocked: false})
    else
      state
    end
  end

  defp notify_worker(state), do: state

  defp parking(state), do: state.turn.parking || Parking.new()

  defp put_parking(state, parking), do: %{state | turn: %{state.turn | parking: parking}}

  # Ends the turn's parking: its waits and early signals go, and every key it
  # used stays closed for later turns.
  defp end_parking(%{turn: %{parking: nil}} = state), do: state
  defp end_parking(state), do: commit_parking(state, [:end_turn])

  defp finish_turn(state) do
    Sandbox.Lease.idle(state.sandbox)
    state = end_parking(state)
    %{state | turn: Turn.finish(state.turn)}
  end

  defp publish_waiting(%{turn: %{parking: parking}} = state) do
    waiting = waiting_info(parking)

    if waiting == parking.published do
      state
    else
      state = put_parking(state, %{parking | published: waiting})
      event = {:waiting, waiting}

      case state.turn.recipient do
        {:stream, ref} -> state |> broadcast(ref, event) |> maybe_dispatch_event(event)
        _run -> publish(state, event)
      end
    end
  end

  defp waiting_info(parking) do
    %{tool_calls: Parking.waiting(parking), wake_at: Park.to_datetime(Parking.next_deadline(parking))}
  end

  # Runs `cancel/2` of the parked calls and the woken ones running again, each
  # in its own unlinked process, so neither the abort nor the session ending
  # stops it, with the state they last parked with.
  defp cancel_parked(%{turn: %{parking: %Parking{} = parking}} = state) do
    if parking.timer, do: Process.cancel_timer(parking.timer)
    tool_map = build_tool_map(state.tools)

    for {id, wait} <- Parking.cancellable(parking), {:ok, tool_spec} <- [Map.fetch(tool_map, wait.tool)] do
      context = tool_context(state, tool_opts(tool_spec), id)
      Task.start(fn -> Tool.cancel(tool_spec, wait.state, context) end)
    end

    :ok
  end

  defp cancel_parked(_state), do: :ok

  defp take_steering(state, messages) do
    with {:ok, steering} <- GenServer.call(state.pid, {:take_steering, state.turn.abort_ref}, :infinity) do
      {:ok, messages ++ steering}
    end
  end

  # Waits until the session has handled every event this worker sent. An
  # agent's `handle_event/2` that stops the turn on one of them shuts this
  # worker down while the session handles it, so the call never returns here
  # and the provider request or tool batch after it never starts.
  defp sync(state), do: GenServer.call(state.pid, :sync, :infinity)

  defp compaction_metadata(state), do: %{agent: state.agent_module, session_id: state.id}

  defp compaction_overhead(state) do
    %{
      input:
        Compaction.data_tokens(state.system_prompt) + Compaction.data_tokens(Enum.map(state.tools, &Tool.to_spec/1)),
      output: state.llm[:max_tokens] || 0
    }
  end

  defp load_project_context(opts, sandbox) do
    if Keyword.get(opts, :load_project_instructions, true) do
      Context.discover(sandbox)
    else
      Context.empty()
    end
  end
end
