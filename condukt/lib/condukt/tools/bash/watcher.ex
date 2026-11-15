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
  #     `{Watcher, pid, status}` when the process ends. If the call dies first
  #     while its session lives, the turn was aborted, so the watcher stops the
  #     sandbox process. If the session died too, the node is going down or the
  #     session crashed, and the process is left for a restarted session to
  #     find by its id.
  #   * the session, once the call parked: the watcher delivers the call's exit
  #     signal when the process ends, and stops when the session does or the
  #     signal is refused because the turn ended.
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
  Starts following process `id` from `offset`, answering to the calling
  process. `context` is the call's tool context.
  """
  def start(sandbox, id, offset, context) do
    owner = self()
    Task.Supervisor.start_child(Condukt.TaskSupervisor, fn -> init(sandbox, id, offset, context, {:call, owner}) end)
  end

  @doc """
  Starts following process `id` for a parked call: the watcher delivers the
  exit signal under `key` to the session.
  """
  def start_parked(sandbox, id, offset, context, key) do
    Task.Supervisor.start_child(Condukt.TaskSupervisor, fn -> init(sandbox, id, offset, context, {:parked, key}) end)
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

  defp init(sandbox, id, offset, context, mode) do
    mode =
      case mode do
        {:call, owner} -> {:call, owner, Process.monitor(owner)}
        parked -> parked
      end

    loop(%{
      sandbox: sandbox,
      id: id,
      offset: offset,
      pending: "",
      context: context,
      session: context.agent,
      session_monitor: Process.monitor(context.agent),
      mode: mode,
      interval: @min_interval,
      errors: 0
    })
  end

  defp loop(state) do
    case Sandbox.read_process(state.sandbox, state.id, state.offset, max_bytes: @read_bytes) do
      {:ok, %{output: output, offset: offset, size: size, status: status}} ->
        state = emit(%{state | offset: offset, errors: 0}, output)

        cond do
          status == :running -> wait(state, output)
          offset < size -> loop(state)
          true -> done(flush(state), status)
        end

      {:error, :not_found} ->
        done(state, {:error, :not_found})

      {:error, reason} when state.errors + 1 >= @max_errors ->
        done(state, {:error, reason})

      {:error, _reason} ->
        wait(%{state | errors: state.errors + 1}, "")
    end
  end

  # Polls quickly while output flows and backs off while it does not.
  defp wait(state, output) do
    interval = if output == "", do: min(state.interval * 2, @max_interval), else: @min_interval
    session_monitor = state.session_monitor

    receive do
      {:park, key, from, ref} ->
        {:call, _owner, monitor} = state.mode
        Process.demonitor(monitor, [:flush])
        send(from, {ref, :ok})
        loop(%{state | mode: {:parked, key}})

      {:DOWN, ^session_monitor, :process, _pid, _reason} ->
        :ok

      {:DOWN, monitor, :process, _pid, reason} when elem(state.mode, 2) == monitor ->
        call_down(state, reason)
    after
      interval -> loop(%{state | interval: interval})
    end
  end

  defp call_down(_state, :normal), do: :ok

  defp call_down(state, _reason) do
    if Process.alive?(state.session), do: Sandbox.stop_process(state.sandbox, state.id)
    :ok
  end

  defp done(%{mode: {:call, owner, _monitor}}, status), do: send(owner, {__MODULE__, self(), status})

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
