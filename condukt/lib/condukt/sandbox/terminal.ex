defmodule Condukt.Sandbox.Terminal do
  @moduledoc """
  A shell in a sandbox that people type into, shared while an agent works.

  The shell is a sandbox process (`c:Condukt.Sandbox.start_process/4`) with
  stdin and a pseudo-terminal, run through util-linux `script`, so it needs
  `c:Condukt.Sandbox.write_process/4`. The terminal process follows its
  output and sends each subscriber `{Condukt.Sandbox.Terminal, id, {:output,
  chunk}}`, and `{Condukt.Sandbox.Terminal, id, {:exit, status}}` once the
  shell ends. Input is written at the offset the terminal tracks, so a write
  repeated after a lost reply lands once.

      {:ok, term} = Condukt.Sandbox.Terminal.start_link(sandbox, id: "pairing")
      :ok = Condukt.Sandbox.Terminal.subscribe(term)
      :ok = Condukt.Sandbox.Terminal.write(term, "make test\\r")

  A subscriber that joins late gets the last 64 KiB from `subscribe/1`'s
  reply first. The shell's size is the pseudo-terminal's default, 80x24:
  resizing needs a PTY the sandbox's node controls, which none offers yet.
  Stopping the terminal kills the shell.
  """

  use GenServer

  alias Condukt.Sandbox

  @scrollback 64 * 1024
  @wait 2_000
  # Consecutive failed reads it rides out, a second apart, as while the
  # sandbox's node restarts, before it reports the shell gone.
  @max_errors 30
  @retry 1_000

  @doc """
  Starts a shell. Options: `:id` (the sandbox process id, default a new
  one), `:shell` (default `bash -il`), `:cwd`, and `:env`.
  """
  def start_link(%Sandbox{} = sandbox, opts \\ []), do: GenServer.start_link(__MODULE__, {sandbox, opts})

  @doc "Subscribes the caller and returns the scrollback so far."
  def subscribe(terminal), do: GenServer.call(terminal, {:subscribe, self()})

  @doc "Writes input, as typed: a newline is `\\r`."
  def write(terminal, data) when is_binary(data), do: GenServer.call(terminal, {:write, data}, 35_000)

  @doc "Stops the terminal and kills its shell."
  def stop(terminal), do: GenServer.stop(terminal)

  @impl true
  def init({sandbox, opts}) do
    id = Keyword.get_lazy(opts, :id, fn -> "condukt-terminal:#{System.unique_integer([:positive])}" end)
    start_opts = [stdin: true, pty: true, cwd: opts[:cwd], env: opts[:env] || []]

    case Sandbox.start_process(sandbox, id, Keyword.get(opts, :shell, "bash -il"), start_opts) do
      :ok ->
        Process.flag(:trap_exit, true)
        send(self(), :read)

        {:ok,
         %{sandbox: sandbox, id: id, offset: 0, stdin: 0, scrollback: "", subscribers: %{}, reader: nil, errors: 0}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    {:reply, {:ok, state.scrollback}, %{state | subscribers: Map.put(state.subscribers, pid, Process.monitor(pid))}}
  end

  def handle_call({:write, data}, _from, state) do
    case Sandbox.write_process(state.sandbox, state.id, data, offset: state.stdin) do
      :ok -> {:reply, :ok, %{state | stdin: state.stdin + byte_size(data)}}
      error -> {:reply, error, state}
    end
  end

  # Reads run in a task, so a long-polled read never holds up input.
  @impl true
  def handle_info(:read, state) do
    %{sandbox: sandbox, id: id, offset: offset} = state
    task = Task.async(fn -> Sandbox.read_process(sandbox, id, offset, wait: @wait) end)
    {:noreply, %{state | reader: task.ref}}
  end

  def handle_info({ref, result}, %{reader: ref} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, %{output: output, offset: offset, status: status, size: size}} ->
        state = output(%{state | offset: offset, reader: nil, errors: 0}, output)

        if status == :running or offset < size do
          send(self(), :read)
          {:noreply, state}
        else
          broadcast(state, {:exit, status})
          {:stop, :normal, state}
        end

      {:error, reason} when reason != :not_found and state.errors < @max_errors ->
        Process.send_after(self(), :read, @retry)
        {:noreply, %{state | reader: nil, errors: state.errors + 1}}

      {:error, reason} ->
        broadcast(state, {:exit, {:error, reason}})
        {:stop, :normal, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, pid, _reason}, state) do
    case state.subscribers do
      %{^pid => ^monitor} -> {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
      _ -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = Sandbox.stop_process(state.sandbox, state.id)
    :ok
  end

  defp output(state, ""), do: state

  defp output(state, chunk) do
    broadcast(state, {:output, chunk})
    scrollback = state.scrollback <> chunk
    keep = min(byte_size(scrollback), @scrollback)
    %{state | scrollback: binary_part(scrollback, byte_size(scrollback) - keep, keep)}
  end

  defp broadcast(state, event) do
    for pid <- Map.keys(state.subscribers), do: send(pid, {__MODULE__, state.id, event})
    :ok
  end
end
