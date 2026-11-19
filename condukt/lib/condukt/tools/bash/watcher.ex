defmodule Condukt.Tools.Bash.Watcher do
  @moduledoc false

  # Follows one sandbox process for a Bash call: reads its log from the
  # sandbox, streams it as tool output, and reports when the process ends.
  #
  # It runs under `Condukt.TaskSupervisor`, apart from the call, because the
  # call does not stay: after the foreground window it parks, and its process
  # ends while the command goes on. The watcher answers to one of two:
  #
  #   * the call, while it waits in the foreground: the watcher sends it
  #     `{Watcher, pid, status}` when the process ends.
  #   * the session, once the call parked: the watcher delivers the call's exit
  #     signal when the process ends, and stops when the session does or the
  #     signal is refused because the turn ended. Read errors, such as a
  #     sandbox's node restarting, are retried until then, never reported:
  #     the command goes on regardless, and the park's own deadline bounds
  #     the wait.
  #
  # In both modes it monitors the call's process and the processes that
  # called it (`$callers`): the session's worker for the turn and the task
  # that hands the park to the session. One of them going down abnormally
  # while the session lives means the turn was aborted, including in the
  # moment between the call parking here and the session recording the park,
  # which the session's own cancel cannot see; the watcher then stops the
  # sandbox process. If the session died too, the node is going down, the
  # session crashed or was drained, and the process is left for a session
  # that takes over to find by its id. The call's process ending normally
  # in the foreground ends the watcher; once parked it is expected.
  #
  # Output goes out a line at a time, so a secret is never split between two
  # chunks that are redacted apart; a line longer than `@max_pending` goes out
  # in pieces.

  alias Condukt.Sandbox
  alias Condukt.Tool
  alias Condukt.Tools.Bash.Exited

  @read_bytes 64 * 1024
  @max_pending 8 * 1024
  @min_interval 200
  @max_interval 2_000
  @max_errors 5

  @doc """
  Starts a watcher that starts process `id` running `command` with `opts`,
  as `Condukt.Sandbox.start_process/4` does, then follows it for the calling
  process; `await_start/1` answers the start. The start runs in the watcher,
  so a call aborted while the command starts has it stopped only once the
  start has finished, and never left behind. `context` is the call's tool
  context.
  """
  def start(sandbox, id, command, opts, context) do
    owners = owners(context)

    Task.Supervisor.start_child(Condukt.TaskSupervisor, fn ->
      init(sandbox, id, 0, context, {:start, command, opts}, owners)
    end)
  end

  @doc "What the start of a watcher from `start/5` returned, as `Condukt.Sandbox.start_process/4` does."
  def await_start(watcher) do
    monitor = Process.monitor(watcher)

    receive do
      {__MODULE__, ^watcher, {:started, result}} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, _pid, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Starts following process `id` for a parked call: the watcher delivers the
  exit signal under `key` to the session. `offset` `nil` starts at the end
  of the output so far.
  """
  def start_parked(sandbox, id, offset, context, key) do
    owners = owners(context)

    Task.Supervisor.start_child(Condukt.TaskSupervisor, fn ->
      init(sandbox, id, offset, context, {:parked, key}, owners)
    end)
  end

  # The calling process, then those that called it, but the session.
  defp owners(context) do
    callers = Enum.reject(Process.get(:"$callers", []), &(&1 == context.agent))
    [{self(), :call} | Enum.map(callers, &{&1, :caller})]
  end

  @doc """
  Hands a watcher over to the session as its call parks. Returns `:ok`, or
  `{:done, status}` when the process ended first.
  """
  def park(watcher, key) do
    monitor = Process.monitor(watcher)
    send(watcher, {:park, key, self(), monitor})

    receive do
      {^monitor, :ok} ->
        Process.demonitor(monitor, [:flush])
        :ok

      {__MODULE__, ^watcher, status} ->
        Process.demonitor(monitor, [:flush])
        {:done, status}

      {:DOWN, ^monitor, :process, _pid, reason} ->
        {:done, {:error, reason}}
    end
  end

  defp init(sandbox, id, offset, context, mode, owners) do
    monitors = Map.new(owners, fn {pid, role} -> {Process.monitor(pid), role} end)

    state = %{
      sandbox: sandbox,
      id: id,
      offset: offset,
      pending: "",
      context: context,
      session: context.agent,
      session_monitor: Process.monitor(context.agent),
      mode: if(match?({:start, _, _}, mode), do: {:call, owners |> hd() |> elem(0)}, else: mode),
      monitors: monitors,
      interval: @min_interval,
      waited: 0,
      errors: 0
    }

    case mode do
      {:start, command, opts} -> start_process(state, command, opts)
      _parked -> loop(state)
    end
  end

  # An owner that went down while the process started is seen once it has:
  # the loop's monitors stop it then.
  defp start_process(%{mode: {:call, owner}} = state, command, opts) do
    result = Sandbox.start_process(state.sandbox, state.id, command, opts)
    send(owner, {__MODULE__, self(), {:started, result}})
    if result in [:ok, {:error, :already_started}], do: loop(state), else: :ok
  end

  # Starting at the end of the output so far.
  defp loop(%{offset: nil} = state) do
    case Sandbox.read_process(state.sandbox, state.id, 0, max_bytes: 0) do
      {:ok, %{size: size}} -> loop(%{state | offset: size})
      {:error, :not_found} -> done(state, {:error, :not_found})
      {:error, _reason} -> wait(%{state | errors: state.errors + 1, waited: 0}, "")
    end
  end

  # Once parked, a sandbox that long-polls holds the read open for up to the
  # interval, and the watcher waits only for what the read left of it. In
  # the foreground it does not, so it notices an aborted call at once.
  defp loop(state) do
    started = System.monotonic_time(:millisecond)
    wait = if parked?(state), do: state.interval, else: 0

    case Sandbox.read_process(state.sandbox, state.id, state.offset, max_bytes: @read_bytes, wait: wait) do
      {:ok, %{output: output, offset: offset, size: size, status: status}} ->
        state = emit(%{state | offset: offset, errors: 0}, output)
        state = %{state | waited: System.monotonic_time(:millisecond) - started}

        cond do
          status == :running -> wait(state, output)
          offset < size -> loop(state)
          true -> done(flush(state), status)
        end

      {:error, reason} ->
        read_failed(state, reason)
    end
  end

  defp read_failed(state, :not_found), do: done(state, {:error, :not_found})

  # In the foreground the call decides, as the session waits on it. Once
  # parked, the park's deadline bounds the retries.
  defp read_failed(state, reason) do
    if not parked?(state) and state.errors + 1 >= @max_errors,
      do: done(state, {:error, reason}),
      else: wait(%{state | errors: state.errors + 1, waited: 0}, "")
  end

  defp parked?(state), do: match?({:parked, _key}, state.mode)

  # Polls quickly while output flows and backs off while it does not.
  defp wait(state, output) do
    interval = if output == "", do: min(state.interval * 2, @max_interval), else: @min_interval
    remaining = if output == "", do: max(state.interval - state.waited, 0), else: 0
    session_monitor = state.session_monitor

    receive do
      {:park, key, from, ref} ->
        send(from, {ref, :ok})
        loop(%{state | mode: {:parked, key}})

      {:DOWN, ^session_monitor, :process, _pid, _reason} ->
        :ok

      {:DOWN, monitor, :process, _pid, reason} when is_map_key(state.monitors, monitor) ->
        owner_down(state, Map.fetch!(state.monitors, monitor), monitor, reason)
    after
      remaining -> loop(%{state | interval: interval})
    end
  end

  # The call ending normally in the foreground leaves nothing to answer to;
  # once parked, and for the processes above it, ending normally is the
  # turn going on.
  defp owner_down(%{mode: {:call, _owner}}, :call, _monitor, :normal), do: :ok

  defp owner_down(state, _role, monitor, :normal),
    do: wait(%{state | monitors: Map.delete(state.monitors, monitor), waited: 0}, "")

  defp owner_down(state, _role, _monitor, _reason) do
    if Process.alive?(state.session), do: Sandbox.stop_process(state.sandbox, state.id)
    :ok
  end

  defp done(%{mode: {:call, owner}}, status), do: send(owner, {__MODULE__, self(), status})

  defp done(%{mode: {:parked, key}} = state, status) do
    Condukt.signal(state.session, Exited, key, status)
  catch
    :exit, _reason -> :ok
  end

  defp emit(state, ""), do: state

  defp emit(state, output) do
    pending = state.pending <> output

    case :binary.matches(pending, "\n") do
      [] when byte_size(pending) < @max_pending ->
        %{state | pending: pending}

      [] ->
        Tool.output(state.context, pending)
        %{state | pending: ""}

      matches ->
        {last, 1} = List.last(matches)
        Tool.output(state.context, binary_part(pending, 0, last + 1))
        %{state | pending: binary_part(pending, last + 1, byte_size(pending) - last - 1)}
    end
  end

  defp flush(%{pending: ""} = state), do: state

  defp flush(state) do
    Tool.output(state.context, state.pending)
    %{state | pending: ""}
  end
end
