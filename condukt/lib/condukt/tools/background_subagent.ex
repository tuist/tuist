defmodule Condukt.Tools.BackgroundSubagent do
  @moduledoc """
  Tool for persistent sub-agents that keep working in the background.

  This tool is injected automatically when an agent registers at least one
  sub-agent role with `background: true`. The parent model spawns named
  sub-agents, messages them, waits for them, stops their current work, and
  lists them. Each one is a `Condukt.Session` that keeps its conversation until
  the parent session stops, and keeps working while the parent answers.

  Answers the parent did not wait for are posted back to it as input, which
  starts a parent turn when the parent is idle and survives an abort of the
  parent's current turn. Roles must run on the native runtime. See the
  [Sub-agents guide](subagents.md).
  """

  use Condukt.Tool

  alias Condukt.Session
  alias Condukt.Tools.BackgroundSubagent.Manager
  alias Condukt.Tools.Subagent

  @actions ["spawn", "send", "wait", "stop", "list"]

  @doc false
  # Starts the manager under `supervisor` and returns this tool for the
  # background roles, or nothing when there are none.
  def tools([], _supervisor), do: []

  def tools(subagents, supervisor) do
    {:ok, manager} = Manager.start(supervisor, self())
    [{__MODULE__, subagents: subagents, manager: manager, supervisor: supervisor}]
  end

  @impl true
  def name, do: "background_subagent"

  @impl true
  def name(_opts), do: name()

  @impl true
  def description do
    """
    Manage persistent sub-agents that work in the background and remember earlier messages. \
    Actions: spawn (name, role, message: the task), \
    send (name, message; follow_up: true queues it after the current answer instead of steering the current work), \
    wait (name: blocks until it is idle and returns its latest answer), \
    stop (name: aborts its current work and drops its queued messages), \
    list. Answers you do not wait for are posted back to you as new messages when they arrive.\
    """
  end

  @impl true
  def description(_opts), do: description()

  @impl true
  def parameters(opts) do
    subagents = Keyword.get(opts, :subagents, [])
    roles = Enum.map(subagents, fn {role, _registration} -> Atom.to_string(role) end)

    input_schemas =
      Enum.flat_map(subagents, fn {_role, {_module, role_opts}} ->
        List.wrap(Keyword.get(role_opts, :input) || Keyword.get(role_opts, :input_schema))
      end)

    properties =
      %{
        action: %{type: "string", enum: @actions, description: "What to do."},
        name: %{type: "string", description: "The sub-agent's name. Every action except list needs it."},
        role: %{type: "string", enum: roles, description: "spawn only. The registered role to start."},
        message: %{type: "string", description: "spawn: the task. send: the message."},
        follow_up: %{
          type: "boolean",
          description: "send only. Queue the message after the current answer instead of steering the current work."
        }
      }
      |> maybe_put_input(input_schemas)

    %{type: "object", properties: properties, required: ["action"]}
  end

  defp maybe_put_input(properties, []), do: properties

  defp maybe_put_input(properties, schemas) do
    Map.put(properties, :input, %{anyOf: schemas, description: "spawn only. Structured input for the role."})
  end

  @impl true
  def call(args, context) do
    manager = Keyword.fetch!(context.opts, :manager)
    action = arg(args, :action)
    name = arg(args, :name)

    cond do
      action == "list" -> {:ok, Manager.list(manager)}
      action not in @actions -> {:error, "unknown action #{inspect(action)}"}
      not is_binary(name) or name == "" -> {:error, "#{action} needs a name"}
      true -> run_action(action, name, args, manager, context)
    end
  catch
    # A manager or child that went away fails the call, not the parent's turn.
    :exit, reason -> {:error, {:background_subagent_unavailable, reason}}
  end

  # The child starts here rather than in the manager, so a slow start, such as
  # MCP servers connecting, holds up only this call.
  defp run_action("spawn", name, args, manager, context) do
    supervisor = Keyword.fetch!(context.opts, :supervisor)

    with {:ok, message} <- fetch_message(args, "spawn"),
         :ok <- Manager.available(manager, name),
         {:ok, role, registration} <- Subagent.lookup(context, arg(args, :role)),
         {:ok, input} <- Subagent.validate_input(args, registration.input_schema),
         prepared = Subagent.prepare_child(registration, context, manager),
         opts = Keyword.put(prepared.session_opts, :notifier, {Manager, manager: manager}),
         {:ok, pid} <- Subagent.start_child(supervisor, registration.agent_module, opts),
         :ok <- require_native(supervisor, pid, registration.agent_module) do
      spec = %{
        pid: pid,
        session_id: Session.id(pid),
        role: role,
        output_schema: prepared.output_schema,
        submit_ref: prepared.ref,
        prompt: Subagent.child_prompt(message, input),
        call_id: Map.get(context, :tool_call_id)
      }

      with {:error, _reason} = error <- Manager.register(manager, name, spec) do
        _ = DynamicSupervisor.terminate_child(supervisor, pid)
        error
      end
    end
  end

  defp run_action("send", name, args, manager, _context) do
    with {:ok, message} <- fetch_message(args, "send") do
      Manager.send_message(manager, name, message, arg(args, :follow_up) == true)
    end
  end

  defp run_action("stop", name, _args, manager, _context), do: Manager.stop(manager, name)

  # The call belongs to the parent's turn, so aborting that turn ends the wait,
  # while the sub-agent, which the turn does not own, keeps working.
  defp run_action("wait", name, _args, manager, context) do
    ref = make_ref()
    turn_ref = Map.get(context, :turn_ref)

    with :ok <- Session.own(context, {:process, self()}) do
      case Manager.wait(manager, name, self(), ref) do
        :waiting ->
          receive do
            {^ref, outcome} ->
              wait_result(name, outcome)

            {:abort, ^turn_ref} ->
              unwait(manager, name, ref)
              {:error, :aborted}
          end

        {:done, outcome} ->
          wait_result(name, outcome)

        {:error, _reason} = error ->
          error
      end
    end
  end

  # An answer delivered as the wait was abandoned goes back to the parent as a
  # report, so it is not lost with the aborted call.
  defp unwait(manager, name, ref) do
    :ok = Manager.unwait(manager, name, ref)

    receive do
      {^ref, outcome} -> Manager.report(manager, name, outcome)
    after
      0 -> :ok
    end
  end

  # Background turns start from queued input, which only native loops take, so
  # a child on another runtime would never start working.
  defp require_native(supervisor, pid, agent_module) do
    if Session.native_runtime?(pid) do
      :ok
    else
      _ = DynamicSupervisor.terminate_child(supervisor, pid)
      {:error, {:background_subagent_requires_native_runtime, agent_module}}
    end
  end

  defp wait_result(name, {:ok, answer}), do: {:ok, %{name: name, status: "idle", answer: answer}}
  defp wait_result(name, :aborted), do: {:ok, %{name: name, status: "stopped"}}
  defp wait_result(name, nil), do: {:ok, %{name: name, status: "idle"}}
  defp wait_result(_name, {:error, reason}), do: {:error, reason}

  defp fetch_message(args, action) do
    case arg(args, :message) do
      message when is_binary(message) and message != "" -> {:ok, message}
      _missing -> {:error, "#{action} needs a message"}
    end
  end

  defp arg(args, key), do: Map.get(args, Atom.to_string(key), Map.get(args, key))
end

defmodule Condukt.Tools.BackgroundSubagent.Manager do
  @moduledoc false

  # Tracks a parent session's background sub-agents. It runs under the
  # parent's sub-agent supervisor, so stopping the parent stops it and every
  # child.
  #
  # Each child gets this module as its notifier, so the manager sees every turn
  # the child runs, also turns started from the child's own steering and
  # follow-up queues. It forwards the events to the parent's notifier, tagged
  # with the call that spawned the child, collects each turn's answer from the
  # turn's own events, and settles the turn on `:done`.
  #
  # The manager never waits on the parent: reports are casts. Its calls to a
  # child are guarded, since the child may die before its `:DOWN` arrives.

  @behaviour Condukt.Notifier

  use GenServer

  alias Condukt.Session
  alias Condukt.Tools.Subagent

  def start(supervisor, parent) do
    DynamicSupervisor.start_child(supervisor, %{
      id: __MODULE__,
      start: {GenServer, :start_link, [__MODULE__, parent]},
      restart: :temporary,
      type: :worker
    })
  end

  def available(manager, name), do: GenServer.call(manager, {:available, name}, :infinity)
  def register(manager, name, spec), do: GenServer.call(manager, {:register, name, spec}, :infinity)

  def send_message(manager, name, message, follow_up?),
    do: GenServer.call(manager, {:send, name, message, follow_up?}, :infinity)

  def stop(manager, name), do: GenServer.call(manager, {:stop, name}, :infinity)
  def list(manager), do: GenServer.call(manager, :list, :infinity)
  def wait(manager, name, pid, ref), do: GenServer.call(manager, {:wait, name, pid, ref}, :infinity)
  def unwait(manager, name, ref), do: GenServer.call(manager, {:unwait, name, ref}, :infinity)
  def report(manager, name, outcome), do: GenServer.cast(manager, {:report, name, outcome})

  @impl Condukt.Notifier
  def publish(session_id, event, opts) do
    send(Keyword.fetch!(opts, :manager), {:child_event, session_id, event})
    :ok
  end

  # Of the child's view changes, only the input its turns start from and the
  # steering that joins them, which its events do not carry. They are filtered
  # in the child's process, so the rest never reaches the manager.
  @impl Condukt.Notifier
  def publish_change(session_id, _epoch, _seq, {kind, _message} = change, opts) when kind in [:run_started, :input] do
    send(Keyword.fetch!(opts, :manager), {:child_input, session_id, change})
    :ok
  end

  def publish_change(_session_id, _epoch, _seq, _change, _opts), do: :ok

  @impl GenServer
  def init(parent) do
    {:ok, %{parent: parent, children: %{}}}
  end

  @impl GenServer
  def handle_call({:available, name}, _from, state) do
    {:reply, if(Map.has_key?(state.children, name), do: already_exists(name), else: :ok), state}
  end

  def handle_call({:register, name, spec}, _from, state) do
    if Map.has_key?(state.children, name) do
      {:reply, already_exists(name), state}
    else
      child =
        spec
        |> Map.take([:pid, :session_id, :role, :call_id, :output_schema, :submit_ref])
        |> Map.merge(%{
          name: name,
          monitor: Process.monitor(spec.pid),
          status: :working,
          error: nil,
          text: "",
          submitted: nil,
          last: nil,
          report_tag: nil,
          waiters: %{}
        })

      safely(fn -> Condukt.follow_up(child.pid, spec.prompt) end)
      {:reply, {:ok, view(child)}, put_child(state, child)}
    end
  end

  def handle_call({:send, name, message, follow_up?}, _from, state) do
    with_child(state, name, fn child ->
      safely(fn -> deliver_message(child.pid, message, follow_up?) end)

      child = %{child | status: :working}
      {:reply, {:ok, view(child)}, put_child(state, child)}
    end)
  end

  def handle_call({:stop, name}, _from, state) do
    with_child(state, name, fn child ->
      safely(fn -> Condukt.abort(child.pid) end)
      {:reply, {:ok, view(%{child | status: :idle})}, state}
    end)
  end

  def handle_call(:list, _from, state) do
    {:reply, state.children |> Map.values() |> Enum.sort_by(& &1.name) |> Enum.map(&view/1), state}
  end

  # The waiter takes the latest answer, so a report of it still queued on the
  # parent is withdrawn: the parent hears each answer once.
  def handle_call({:wait, name, pid, ref}, _from, state) do
    with_child(state, name, fn
      %{status: :idle} = child ->
        {:reply, {:done, child.last}, put_child(state, claim(child, state))}

      child ->
        waiters = Map.put(child.waiters, ref, {pid, Process.monitor(pid)})
        {:reply, :waiting, put_child(state, %{child | waiters: waiters})}
    end)
  end

  def handle_call({:unwait, name, ref}, _from, state) do
    case Map.fetch(state.children, name) do
      {:ok, child} -> {:reply, :ok, put_child(state, drop_waiter(child, ref))}
      :error -> {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_cast({:report, name, outcome}, state) do
    case Map.fetch(state.children, name) do
      {:ok, child} ->
        {:noreply, put_child(state, report_answer(child, outcome, state))}

      :error ->
        _ = report_answer(%{name: name, report_tag: nil}, outcome, state)
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:child_event, session_id, event}, state) do
    case Enum.find(Map.values(state.children), &(&1.session_id == session_id)) do
      nil ->
        {:noreply, state}

      child ->
        Session.forward_event(state.parent, nil, {:subagent, child.call_id, event})
        {:noreply, put_child(state, track(child, event, state))}
    end
  end

  def handle_info({:child_input, session_id, change}, state) do
    case Enum.find(Map.values(state.children), &(&1.session_id == session_id)) do
      nil -> :ok
      child -> Session.background_input(state.parent, child.name, change)
    end

    {:noreply, state}
  end

  def handle_info({ref, :operation_submit, submitted}, state) do
    case Enum.find(Map.values(state.children), &(&1.submit_ref == ref)) do
      nil -> {:noreply, state}
      child -> {:noreply, put_child(state, %{child | submitted: submitted})}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    case Enum.find(Map.values(state.children), &(&1.monitor == monitor)) do
      nil ->
        children = Map.new(state.children, fn {name, child} -> {name, drop_waiter_monitor(child, monitor)} end)
        {:noreply, %{state | children: children}}

      child ->
        deliver(%{child | status: :idle}, {:error, {:session_exit, reason}}, state)
        Session.background_changed(state.parent, child.name, nil)
        {:noreply, %{state | children: Map.delete(state.children, child.name)}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  # The answer is the text of the turn's last model response, collected as it
  # streams, so a later turn of the same child cannot replace it.
  defp track(child, :agent_start, _state), do: %{child | status: :working, error: nil, text: ""}
  defp track(child, :turn_start, _state), do: %{child | text: ""}
  defp track(child, {:text, chunk}, _state), do: %{child | text: child.text <> chunk}
  defp track(child, {:error, reason}, _state), do: %{child | error: child.error || reason}
  defp track(child, :done, state), do: settle(child, state)
  defp track(child, _event, _state), do: child

  # A turn of the child ended. The child is idle unless queued input already
  # started its next turn.
  defp settle(child, state) do
    outcome =
      case child.error do
        nil -> answer(child)
        :aborted -> :aborted
        reason -> {:error, reason}
      end

    status = if busy?(child.pid), do: :working, else: :idle
    child = %{child | status: status, error: nil, text: "", submitted: nil, last: outcome}
    deliver(child, outcome, state)
  end

  defp answer(%{output_schema: nil} = child), do: {:ok, child.text}
  defp answer(%{submitted: nil}), do: {:error, :no_result_submitted}
  defp answer(child), do: Subagent.validate_output(child.output_schema, child.submitted)

  # Waiters get the outcome once the child is idle. Any other answer is
  # reported to the parent; a stopped turn has nothing to report.
  defp deliver(%{status: :idle, waiters: waiters} = child, outcome, _state) when map_size(waiters) > 0 do
    Enum.each(waiters, fn {ref, {pid, monitor}} ->
      Process.demonitor(monitor, [:flush])
      send(pid, {ref, outcome})
    end)

    %{child | waiters: %{}}
  end

  defp deliver(child, outcome, state), do: report_answer(child, outcome, state)

  defp report_answer(child, outcome, _state) when outcome in [nil, :aborted], do: child

  defp report_answer(child, outcome, state) do
    tag = make_ref()
    Session.report(state.parent, tag, report_text(child.name, outcome))
    %{child | report_tag: tag}
  end

  defp claim(%{report_tag: nil} = child, _state), do: child

  defp claim(child, state) do
    Session.withdraw_report(state.parent, child.report_tag)
    %{child | report_tag: nil}
  end

  defp report_text(name, {:ok, answer}) when is_binary(answer), do: "[subagent #{name} answered] #{answer}"
  defp report_text(name, {:ok, answer}), do: "[subagent #{name} answered] #{JSON.encode!(answer)}"
  defp report_text(name, {:error, reason}), do: "[subagent #{name} failed: #{inspect(reason)}]"

  defp busy?(pid) do
    Session.busy?(pid)
  catch
    :exit, _reason -> false
  end

  defp deliver_message(pid, message, true), do: Condukt.follow_up(pid, message)
  defp deliver_message(pid, message, false), do: Condukt.steer(pid, message)

  defp safely(fun) do
    fun.()
  catch
    :exit, _reason -> :ok
  end

  defp already_exists(name), do: {:error, "#{name} already exists; use send"}

  defp with_child(state, name, fun) do
    case Map.fetch(state.children, name) do
      {:ok, child} -> fun.(child)
      :error -> {:reply, {:error, "no background sub-agent named #{name}"}, state}
    end
  end

  defp drop_waiter(child, ref) do
    case Map.pop(child.waiters, ref) do
      {{_pid, monitor}, waiters} ->
        Process.demonitor(monitor, [:flush])
        %{child | waiters: waiters}

      {nil, _waiters} ->
        child
    end
  end

  defp drop_waiter_monitor(child, monitor) do
    %{child | waiters: Map.reject(child.waiters, fn {_ref, {_pid, m}} -> m == monitor end)}
  end

  # Tells the parent session when what its view shows of a child changes.
  defp put_child(state, child) do
    entry = entry(child)
    if entry(state.children[child.name]) != entry, do: Session.background_changed(state.parent, child.name, entry)
    %{state | children: Map.put(state.children, child.name, child)}
  end

  defp entry(nil), do: nil

  defp entry(child) do
    %{name: child.name, role: child.role, session_id: child.session_id, call_id: child.call_id, status: child.status}
  end

  defp view(child) do
    %{name: child.name, role: child.role, session_id: child.session_id, status: Atom.to_string(child.status)}
  end
end
