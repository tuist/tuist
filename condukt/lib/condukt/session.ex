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
    Message,
    Retry,
    Sandbox,
    Secrets,
    SessionID,
    SessionStore,
    Telemetry,
    Tool,
    TraceContext
  }

  alias Condukt.MCP
  alias Condukt.Notifier
  alias Condukt.Session.Compaction
  alias Condukt.Session.Translate
  alias Condukt.Session.Turn
  alias Condukt.Session.View
  alias Condukt.SessionStore.Snapshot
  alias Condukt.Tool.Inline
  alias Condukt.Tools.Subagent

  require Logger

  @default_timeout 300_000
  @default_max_turns 50

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
    :subagents,
    :subagent_supervisor,
    :cwd,
    :sandbox,
    :secrets,
    :mcp_registry,
    :notifier,
    :session_store,
    :session_store_opts,
    :redactor,
    :retry,
    :project_context,
    :user_state,
    compaction: %Compaction{},
    view: %Condukt.Session.View{},
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
      |> Keyword.put_new(:subagents, agent_subagents(agent_module))
      |> Keyword.put_new(:mcp_servers, agent_mcp_servers(agent_module))
      |> put_configured_opt(config, :cwd, &File.cwd!/0)
      |> put_configured_opt(config, :sandbox, fn -> agent_sandbox(agent_module) end)
      |> put_configured_opt(config, :secrets, fn -> agent_secrets(agent_module) end)
      |> put_configured_opt(config, :session_store)
      |> put_configured_opt(config, :session_store_key)
      |> put_configured_opt(config, :session_store_opts, fn -> [] end)
      |> put_configured_opt(config, :compactor)
      |> put_configured_opt(config, :background_compaction)
      |> put_configured_opt(config, :redactor)
      |> put_configured_opt(config, :retry)

    with :ok <- validate_llm_request_options(agent_opts[:llm_request_options]),
         snapshot = load_snapshot(agent_opts[:session_store], agent_opts),
         model = restore_value(agent_opts, :model, snapshot && snapshot.model),
         {:ok, compaction} <- Compaction.new(agent_opts[:compactor], agent_opts[:background_compaction], model) do
      agent_opts =
        agent_opts
        |> Keyword.put(:model, model)
        |> Keyword.put(:max_tokens, agent_opts[:max_tokens] || (agent_opts[:llm_request_options] || [])[:max_tokens])
        |> Keyword.put(:restored_snapshot, snapshot)
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

  defp session_destination({:via, module, name}), do: module.whereis_name(name)

  defp session_destination({name, node}) when is_atom(name) and is_atom(node), do: {name, node}

  @doc """
  Streams a prompt, returning an enumerable of events.
  """
  def stream(agent, prompt, opts \\ []) do
    opts = attach_trace_context(opts)

    Stream.resource(
      fn ->
        ref = make_ref()
        :ok = stream_to(agent, prompt, opts, ref)
        ref
      end,
      fn ref ->
        receive do
          {^ref, :done} ->
            {:halt, ref}

          {^ref, event} ->
            {[event], ref}
        after
          @default_timeout ->
            {[{:error, :timeout}], ref}
        end
      end,
      fn ref ->
        GenServer.cast(agent, {:unsubscribe, self(), ref})
      end
    )
  end

  @doc false
  # Subscribes the caller under `ref` and starts a streaming turn, for callers
  # that consume the events themselves, such as a foreground sub-agent call.
  def stream_to(agent, prompt, opts, ref) do
    :ok = GenServer.call(agent, {:subscribe, self(), ref})
    GenServer.cast(agent, {:stream, prompt, opts, ref})
  end

  @doc false
  # Records work a tool call started as owned by the turn that made the call,
  # so aborting the turn aborts it first. Returns `{:error, :aborted}` when that
  # turn is already over; the caller then stops the work itself.
  def own(%{agent: session, turn_ref: turn_ref}, owned) when is_pid(session) and is_reference(turn_ref) do
    GenServer.call(session, {:own, turn_ref, owned}, :infinity)
  end

  def own(_tool_context, _owned), do: :ok

  @doc false
  # Publishes an event from a sub-agent where the session's own events go: the
  # streaming turn `turn_ref` names, or with `nil` the notifier only, for
  # background sub-agents that outlive the turn that started them.
  def forward_event(session, turn_ref, event) do
    GenServer.cast(session, {:subagent_event, turn_ref, event})
  end

  @doc false
  # Whether a turn runs or input other than reports waits to start one.
  def busy?(agent) do
    GenServer.call(agent, :busy?)
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
    GenServer.cast(agent, {:unsubscribe, self(), :view})
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
  after that error, without waiting for in-flight inference or admitted tools.
  Native retry backoff wakes immediately. Already-admitted work may finish,
  but its late events and results cannot affect the session or a replacement turn.
  """
  def abort(agent) do
    GenServer.call(agent, :abort)
  end

  @doc """
  Runs the configured compactor against the current message history.

  No-op when no compactor is configured. The compacted snapshot is
  immediately persisted if a session store is configured. With background
  compaction enabled, waits without blocking the session process, and returns
  `{:error, :already_streaming}` if a turn is active.
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
          emit_secret_resolve(id, agent_module, secrets)
          subagents = normalize_subagents(Keyword.get(opts, :subagents, []))
          {:ok, subagent_supervisor} = maybe_start_subagent_supervisor(subagents)
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
                request_options: opts[:llm_request_options]
              },
              configured_system_prompt: configured_system_prompt,
              system_prompt: Context.compose_system_prompt(configured_system_prompt, project_context.prompt),
              tools: tools ++ Subagent.tools(subagents, subagent_supervisor),
              subagents: subagents,
              subagent_supervisor: subagent_supervisor,
              cwd: cwd,
              sandbox: sandbox,
              secrets: secrets,
              mcp_registry: mcp_registry,
              session_store: session_store,
              session_store_opts: session_store_opts(opts),
              compaction: Keyword.fetch!(opts, :compaction),
              redactor: opts[:redactor],
              retry: Retry.normalize(opts[:retry]),
              project_context: project_context,
              user_state: user_state,
              assigns: Keyword.get(opts, :assigns, %{})
            }
            |> restore_messages(snapshot)

          {:ok, init_view(state)}
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

  def handle_call({:subscribe, pid, ref}, _from, state) do
    # Monitored, because the only other way out of this list is an explicit
    # unsubscribe and a subscriber that crashes never sends one. Without this a
    # session accumulates dead pids for as long as it lives and keeps sending
    # to every one of them.
    monitor = Process.monitor(pid)
    {:reply, :ok, %{state | turn: Turn.subscribe(state.turn, pid, ref, monitor)}}
  end

  def handle_call(:view, _from, state) do
    {:reply, state.view, state}
  end

  # Watchers listen under `:view`. Replying with the view in the same call that
  # subscribes is what leaves no gap and no repeat between the two.
  def handle_call({:watch, pid}, _from, state) do
    if pid in Turn.listeners(state.turn, :view) do
      {:reply, state.view, state}
    else
      turn = Turn.subscribe(state.turn, pid, :view, Process.monitor(pid))
      {:reply, state.view, %{state | turn: turn}}
    end
  end

  def handle_call(:history, _from, state) do
    {:reply, state.messages, state}
  end

  def handle_call(:id, _from, state) do
    {:reply, state.id, state}
  end

  def handle_call(:clear, _from, state) do
    state = abort_turn(state)
    compaction = %{Compaction.cancel(state.compaction) | attempted: nil, usage: nil}
    state = sync_messages(%{state | messages: [], compaction: compaction})
    persist_or_clear_snapshot(state, :clear)
    {:reply, :ok, maybe_start_queued_turn(state)}
  end

  def handle_call(:abort, _from, state) do
    {:reply, :ok, state |> abort_turn() |> maybe_start_queued_turn()}
  end

  def handle_call({:own, ref, owned}, _from, state) do
    if state.turn.streaming and ref == state.turn.abort_ref do
      {:reply, :ok, %{state | turn: Turn.own(state.turn, owned)}}
    else
      {:reply, {:error, :aborted}, state}
    end
  end

  def handle_call({:take_steering, ref}, _from, state) do
    if state.turn.streaming and ref == state.turn.abort_ref do
      {steering, turn} = Turn.take_steering(state.turn)
      state = sync_queue(%{state | turn: turn})
      state = Enum.reduce(View.redact(steering, outbound_redactor(state)), state, &record(&2, {:input, &1}))
      {:reply, {:ok, steering}, state}
    else
      {:reply, {:error, :aborted}, state}
    end
  end

  def handle_call(:busy?, _from, state) do
    {:reply, state.turn.streaming or Turn.input_waiting?(state.turn), state}
  end

  def handle_call(:native_runtime?, _from, state) do
    {:reply, match?({Native, _}, state.runtime), state}
  end

  def handle_call({:check_turn, ref}, _from, state) do
    result = if state.turn.streaming and ref == state.turn.abort_ref, do: :ok, else: {:error, :aborted}
    {:reply, result, state}
  end

  def handle_call(:compact, from, state) do
    cond do
      not Compaction.enabled?(state.compaction) ->
        state = maybe_compact(state)
        persist_snapshot(state)
        {:reply, :ok, sync_messages(state)}

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

  def handle_cast({:report, tag, text}, state) do
    {:noreply, maybe_start_queued_turn(%{state | turn: Turn.report(state.turn, tag, Message.user(text))})}
  end

  def handle_cast({:withdraw_report, tag}, state) do
    {:noreply, sync_queue(%{state | turn: Turn.withdraw_report(state.turn, tag)})}
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
      {:noreply, record(state, View.redact(event, outbound_redactor(state)))}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:background_subagent, name, entry}, state) do
    {:noreply, record(state, {:background, name, entry})}
  end

  def handle_cast({:background_input, name, change}, state) do
    if Map.has_key?(state.view.background, name) do
      {:noreply, record(state, {:background_event, name, View.redact(change, outbound_redactor(state))})}
    else
      {:noreply, state}
    end
  end

  # Background sub-agents outlive turns, so their events build each one's run
  # under its name in the view rather than under a call of the current turn.
  def handle_cast({:subagent_event, nil, event}, state) do
    Notifier.publish(state.notifier, state.id, event)

    with {:subagent, call_id, child_event} <- event,
         {name, _entry} <- Enum.find(state.view.background, &match?({_name, %{call_id: ^call_id}}, &1)) do
      {:noreply, record(state, {:background_event, name, View.redact(child_event, outbound_redactor(state))})}
    else
      _other -> {:noreply, state}
    end
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

  def handle_cast({:run_complete, turn_ref, from, result}, state) do
    if turn_ref == state.turn.abort_ref do
      handle_cast({:run_complete, from, result}, state)
    else
      {:noreply, state}
    end
  end

  def handle_cast({:run_complete, from, {result, messages, assigns}}, state) do
    GenServer.reply(from, result)
    # A failed native run may have already adopted a prefix at a checkpoint.
    # Its original captured history must not restore that discarded prefix.
    messages =
      if match?({:error, _}, result) and Compaction.enabled?(state.compaction), do: state.messages, else: messages

    state = %{state | turn: Turn.finish(state.turn), messages: messages, assigns: assigns}

    state =
      if match?({:ok, _}, result) or not Compaction.enabled?(state.compaction), do: maybe_compact(state), else: state

    persist_snapshot(state)
    {:noreply, state |> view_run_finished(run_error(result)) |> maybe_start_queued_turn()}
  end

  def handle_cast({:stream_complete, turn_ref, ref, result}, state) do
    if turn_ref == state.turn.abort_ref do
      handle_cast({:stream_complete, ref, result}, state)
    else
      {:noreply, state}
    end
  end

  def handle_cast({:stream_complete, ref, {:ok, messages, _response, assigns}}, state) do
    state = broadcast(state, ref, :done)
    state = %{state | turn: Turn.finish(state.turn), messages: messages, assigns: assigns} |> maybe_compact()
    persist_snapshot(state)
    {:noreply, state |> view_run_finished(nil) |> maybe_start_queued_turn()}
  end

  def handle_cast({:stream_complete, ref, result}, state) do
    state = broadcast(state, ref, :done)
    state = %{state | turn: Turn.finish(state.turn)} |> view_run_finished(run_error(result))
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

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    {:noreply, %{state | turn: Turn.drop_monitored(state.turn, monitor)}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
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
      case agent_loop(state, messages, max_turns, 0) do
        {:ok, final_messages, response, final_assigns} ->
          {{:ok, response}, final_messages, final_assigns}

        {:error, reason} ->
          {{:error, reason}, messages, state.assigns}
      end
    end)
  end

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
      result = streaming_loop(state, messages, max_turns, 0, emit, abort_ref)
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
         {:ok, messages} <- compaction_checkpoint(state, messages) do
      agent_turn(state, messages, max_turns, turn)
    end
  end

  defp agent_turn(state, messages, max_turns, turn) do
    tools = build_req_llm_tools(state.tools, state)

    call = &ReqLLM.generate_text(state.llm.model, &1, llm_opts(state, tools))
    {result, messages} = llm_request(state, messages, turn, false, fn -> false end, call)

    with {:ok, response} <- result,
         :ok <- check_turn(state) do
      record_compaction_usage(state, response, messages)
      assistant_message = Translate.response_to_message(response)
      messages = messages ++ [assistant_message]
      view_event = &GenServer.cast(state.pid, {:view_event, state.turn.abort_ref, &1})
      text = Message.text(assistant_message)
      if text != "", do: view_event.({:text, text})

      if Message.has_tool_calls?(assistant_message) do
        {tool_results, messages, assigns_diff} = execute_tool_calls(state, assistant_message, messages, view_event)
        messages = messages ++ tool_results
        state = %{state | assigns: Map.merge(state.assigns, assigns_diff)}
        agent_loop(state, messages, max_turns, turn + 1)
      else
        response_text = Message.text(assistant_message)
        {:ok, messages, response_text, state.assigns}
      end
    end
  end

  defp streaming_loop(state, messages, max_turns, turn, _emit, _abort_ref) when turn >= max_turns do
    response = extract_text_response(messages)
    {:ok, messages, response, state.assigns}
  end

  defp streaming_loop(%{turn: %{abort_ref: abort_ref}} = state, messages, max_turns, turn, emit, abort_ref) do
    with {:ok, messages} <- take_steering(state, messages),
         {:ok, messages} <- compaction_checkpoint(state, messages) do
      emit.(:turn_start)
      stream_turn(state, messages, max_turns, turn, emit, abort_ref)
    else
      {:error, reason} -> emit_stream_error(emit, reason)
    end
  end

  defp streaming_loop(_state, _messages, _max_turns, _turn, _emit, _abort_ref) do
    {:error, :aborted}
  end

  defp start_run(state, prompt, opts, from) do
    state = view_run_started(state, prompt, opts)
    state = %{state | turn: Turn.start(state.turn, {:run, from}, length(state.messages))}
    parent = self()
    trace_context = TraceContext.capture(opts)

    {:ok, worker} =
      Task.start(fn ->
        TraceContext.attach(trace_context)
        result = do_run(state, prompt, opts)
        GenServer.cast(parent, {:run_complete, state.turn.abort_ref, from, result})
      end)

    %{state | turn: %{state.turn | worker: worker}}
  end

  defp start_stream(state, prompt, opts, subscriber_ref) do
    state = view_run_started(state, prompt, opts)
    state = %{state | turn: Turn.start(state.turn, {:stream, subscriber_ref}, length(state.messages))}
    {:ok, worker} = start_stream_task(state, prompt, opts, subscriber_ref)
    %{state | turn: %{state.turn | worker: worker}}
  end

  defp start_stream_task(state, prompt, opts, subscriber_ref) do
    parent = self()
    abort_ref = state.turn.abort_ref
    trace_context = TraceContext.capture(opts)

    Task.start(fn ->
      TraceContext.attach(trace_context)

      result =
        do_stream(
          state,
          prompt,
          opts,
          &broadcast_stream_event(parent, abort_ref, subscriber_ref, &1),
          abort_ref
        )

      GenServer.cast(parent, {:stream_complete, abort_ref, subscriber_ref, result})
    end)
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
         :ok <- check_turn(state) do
      handle_stream_response(state, response, messages, max_turns, turn, emit, abort_ref)
    else
      {:error, reason} ->
        emit_stream_error(emit, reason)
    end
  end

  defp handle_stream_response(state, response, messages, max_turns, turn, emit, abort_ref) do
    record_compaction_usage(state, response, messages)
    assistant_message = Translate.response_to_message(response)
    text = ReqLLM.Response.text(response) || ""
    messages = messages ++ [assistant_message]
    emit.(:turn_end)

    case Message.has_tool_calls?(assistant_message) do
      true ->
        {tool_results, messages, assigns_diff} =
          execute_tool_calls(state, assistant_message, messages, emit)

        state = %{state | assigns: Map.merge(state.assigns, assigns_diff)}
        streaming_loop(state, messages ++ tool_results, max_turns, turn + 1, emit, abort_ref)

      false ->
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
            {:ok, result, _assigns} when is_binary(result) -> Secrets.redact_text(state.secrets, result)
            {:ok, result, _assigns} -> JSON.encode!(Secrets.redact_result(state.secrets, result))
            {:ok, result} when is_binary(result) -> Secrets.redact_text(state.secrets, result)
            {:ok, result} -> JSON.encode!(Secrets.redact_result(state.secrets, result))
            {:error, reason} -> "Error: #{inspect(reason)}"
          end
        end
      )
    end)
  end

  # One path for both callers. Each announces the calls before they run and
  # each result as it lands through its emitter: the streaming one to its
  # subscribers and notifier, the plain one to the view only.
  defp execute_tool_calls(state, assistant_message, messages, emit) do
    tool_calls = Message.tool_calls(assistant_message)
    tool_map = build_tool_map(state.tools)
    trace_context = TraceContext.current()

    Enum.each(tool_calls, fn {id, name, args} -> emit.({:tool_call, name, id, args}) end)

    {tool_results, assigns_diff} =
      tool_calls
      |> Task.async_stream(
        fn {id, _name, _args} = tool_call ->
          TraceContext.attach(trace_context)

          case check_turn(state) do
            :ok -> execute_tool_call(tool_map, tool_call, state)
            {:error, :aborted} -> {Message.tool_result(id, {:error, :aborted}), %{}}
          end
        end,
        ordered: true,
        timeout: tool_timeout(state)
      )
      |> Enum.zip(tool_calls)
      |> Enum.map(&task_result_to_tool_result/1)
      |> Enum.map(fn {result, assigns} ->
        emit.({:tool_result, result.tool_call_id, Message.tool_result_content(result)})
        {result, assigns}
      end)
      |> split_results_and_assigns()

    {tool_results, messages, assigns_diff}
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

  defp execute_tool_call(tool_map, {id, name, args}, state) do
    metadata = %{
      tool: name,
      tool_call_id: id,
      args: args,
      session_id: state.id,
      agent: state.agent_module
    }

    Telemetry.span(
      :tool_call,
      metadata,
      fn -> execute_tool(tool_map, name, args, state, id) end,
      &tool_call_stop_metadata/1
    )
  end

  defp tool_call_stop_metadata({%Message{content: {:error, _} = error}, _assigns}), do: %{status: :error, result: error}

  defp tool_call_stop_metadata({%Message{content: content}, _assigns}), do: %{status: :ok, result: content}

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

  defp task_result_to_tool_result({{:ok, {message, assigns}}, _tool_call}), do: {message, assigns}

  defp task_result_to_tool_result({{:exit, reason}, {id, _name, _args}}) do
    {Message.tool_result(id, {:error, reason}), %{}}
  end

  defp execute_tool(tool_map, name, args, state, id) do
    case Map.fetch(tool_map, name) do
      :error ->
        {Message.tool_result(id, {:error, "Unknown tool: #{name}"}), %{}}

      {:ok, tool_spec} ->
        emit_secret_access(state, name, id)
        execute_known_tool(tool_spec, args, state, id)
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

  defp execute_known_tool({module, opts}, args, state, id) do
    execute_tool_spec({module, opts}, args, tool_context(state, opts, id), id)
  end

  defp execute_known_tool(tool_spec, args, state, id) do
    execute_tool_spec(tool_spec, args, tool_context(state, [], id), id)
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
      sandbox: state.sandbox,
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

  defp execute_tool_spec(tool_spec, args, context, id) do
    case Tool.execute(tool_spec, args, context) do
      {:ok, result, assigns} when is_map(assigns) ->
        {Message.tool_result(id, Secrets.redact_result(context[:secrets], result)), assigns}

      {:ok, result} ->
        {Message.tool_result(id, Secrets.redact_result(context[:secrets], result)), %{}}

      {:error, reason} ->
        {Message.tool_result(id, Secrets.redact_result(context[:secrets], {:error, reason})), %{}}
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

  # Returns the state, since every published event is also a view change.
  defp broadcast(state, ref, event) do
    broadcast_subscribers(state, ref, event)
    Notifier.publish(state.notifier, state.id, event)
    record(state, View.redact(event, outbound_redactor(state)))
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

  defp load_snapshot(nil, _opts), do: nil

  defp load_snapshot(session_store, opts) do
    case SessionStore.load(session_store, session_store_opts(opts)) do
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

    case SessionStore.save(state.session_store, snapshot, session_store_opts(state)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to persist session snapshot: #{inspect(reason)}")
        :ok
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
    with :ok <- check_turn(state) do
      opts = Compaction.compactor_opts(phase)
      {:ok, Compaction.apply(state.compaction.spec, messages, compaction_metadata(state), opts)}
    end
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
         {:ok, compacted} when compacted != messages <- compaction_checkpoint(state, messages, :overflow) do
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
      with :ok <- check_turn(state), do: call.(context)
    end

    Telemetry.span(
      :llm_turn,
      llm_turn_metadata(state, messages, turn, streaming?),
      fn -> Retry.with_retry(state.retry, emitted?, attempt, &wait_for_retry(state, &1)) end,
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
    if messages != state.messages, do: persist_snapshot(updated)
    sync_messages(updated)
  end

  defp release_compaction_waiter(%{compaction: %{waiter: nil}} = state, _result), do: state

  defp release_compaction_waiter(%{compaction: %{waiter: {from, _, _, _}}} = state, result) do
    GenServer.reply(from, result)
    %{state | compaction: %{state.compaction | waiter: nil}}
  end

  defp abort_turn(state) do
    state = release_compaction_waiter(state, {:error, :aborted})
    if state.turn.worker, do: send(state.turn.worker, {:abort, state.turn.abort_ref})
    # Bottom-up: what the turn owns is aborted before its own caller hears.
    Enum.each(state.turn.owned, &abort_owned(&1, state.turn.abort_ref))

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

    # Pending callers never started, so only they hear, not the notifier.
    Enum.each(state.turn.pending, fn
      {_prompt, _opts, {:run, from}} ->
        GenServer.reply(from, {:error, :aborted})

      {_prompt, _opts, {:stream, ref}} ->
        broadcast_subscribers(state, ref, {:error, :aborted})
        broadcast_subscribers(state, ref, :done)
    end)

    view_run_finished(%{state | turn: Turn.abort(state.turn)}, :aborted)
  end

  defp abort_owned({:session, pid}, _turn_ref) do
    GenServer.call(pid, :abort)
  catch
    :exit, _reason -> :ok
  end

  defp abort_owned({:process, pid}, turn_ref), do: send(pid, {:abort, turn_ref})

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

      {{prompt, opts, {:run, from}}, turn} ->
        start_run(%{state | turn: turn}, prompt, opts, from)

      {{prompt, opts, {:stream, ref}}, turn} ->
        start_stream(%{state | turn: turn}, prompt, opts, ref)

      {%Message{} = message, turn} ->
        state = start_stream(%{state | turn: turn}, message.content, [images: message.images], make_ref())
        %{state | turn: %{state.turn | queued: true}}
    end
  end

  defp start_queued_turn(state), do: state

  # ============================================================================
  # View
  # ============================================================================

  defp init_view(state) do
    {runtime, _opts} = state.runtime

    agent = %{
      module: state.agent_module,
      model: model_name(state.llm.model),
      thinking_level: state.llm.thinking_level,
      tools: Enum.map(state.tools, &Tool.name/1),
      runtime: runtime
    }

    %{state | view: View.new(state.id, agent, View.redact(state.messages, outbound_redactor(state)))}
  end

  # Only the name: a model spec can carry provider options a viewer must not see.
  defp model_name(model) when is_binary(model), do: model
  defp model_name(%{provider: provider, id: id}), do: "#{provider}:#{id}"
  defp model_name(_model), do: nil

  # Numbers a change, folds it into the view, and sends it to the watchers and
  # the notifier. Every change goes through here, in the session process, so
  # its order is the order every viewer applies it in.
  defp record(state, change) do
    %View{epoch: epoch, seq: seq} = state.view
    {:ok, view} = View.advance(state.view, epoch, seq + 1, change)

    for pid <- Turn.listeners(state.turn, :view) do
      send(pid, {:condukt_change, state.id, epoch, seq + 1, change})
    end

    Notifier.publish_change(state.notifier, state.id, epoch, seq + 1, change)
    %{state | view: view}
  end

  defp sync_queue(state) do
    items = state.turn |> View.queue() |> View.redact(outbound_redactor(state))
    if items == state.view.queue, do: state, else: record(state, {:queue, items})
  end

  defp view_run_started(state, prompt, opts) do
    [message] = View.redact([Message.user(prompt, opts[:images] || [])], outbound_redactor(state))
    state |> sync_queue() |> record({:run_started, message})
  end

  # Ends the view's run, adding to the history what the turn added. History a
  # compaction rewrote during the turn is replaced after the run ends.
  defp view_run_finished(%{view: %View{run: nil}} = state, _error), do: sync_messages(state)

  defp view_run_finished(state, error) do
    messages = View.redact(state.messages, outbound_redactor(state))
    held = state.view.messages

    if List.starts_with?(messages, held) do
      record(state, {:run_finished, error, Enum.drop(messages, length(held))})
    else
      state |> record({:run_finished, error, []}) |> record({:messages, :replace, messages})
    end
  end

  # A turn in flight owns the history until it ends, including what a
  # compaction checkpoint adopts mid-turn, so only an idle session syncs it.
  defp sync_messages(%{turn: %{streaming: true}} = state), do: state

  defp sync_messages(state) do
    messages = View.redact(state.messages, outbound_redactor(state))
    held = state.view.messages

    cond do
      messages == held -> state
      List.starts_with?(messages, held) -> record(state, {:messages, :append, Enum.drop(messages, length(held))})
      true -> record(state, {:messages, :replace, messages})
    end
  end

  defp run_error({:error, reason}), do: reason
  defp run_error(_result), do: nil

  defp take_steering(state, messages) do
    with {:ok, steering} <- GenServer.call(state.pid, {:take_steering, state.turn.abort_ref}, :infinity) do
      {:ok, messages ++ steering}
    end
  end

  defp wait_for_retry(state, delay) do
    with :ok <- check_turn(state) do
      abort_ref = state.turn.abort_ref

      receive do
        {:abort, ^abort_ref} -> {:error, :aborted}
      after
        delay -> :ok
      end
    end
  end

  defp check_turn(state), do: GenServer.call(state.pid, {:check_turn, state.turn.abort_ref}, :infinity)

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
