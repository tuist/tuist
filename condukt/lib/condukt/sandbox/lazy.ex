defmodule Condukt.Sandbox.Lazy do
  @moduledoc """
  A sandbox that starts another on first use and lets it go when idle, for
  a second machine a session needs now and then, such as a Mac beside a
  Linux one.

      {:ok, mac} =
        Condukt.Sandbox.new(Condukt.Sandbox.Lazy,
          sandbox: {MyApp.MacSandbox, image: "macos-15"},
          idle_after: :timer.minutes(10),
          before_use: fn mac -> Condukt.Sandbox.Sync.mirror(linux, ".", mac, "work/repo") end
        )

      tools: [
        Condukt.Tools.Bash,
        {Condukt.Tools.Bash, name: "MacBash", sandbox: mac},
        {Condukt.Tools.Read, name: "MacRead", sandbox: mac}
      ]

  A tool given `sandbox:` runs against it instead of the session's (see the
  Sandbox guide). Options:

    * `:sandbox` — the sandbox to start, as the session's `:sandbox` takes it
    * `:idle_after` — milliseconds without a call after which it is let go
      (default ten minutes): `c:Condukt.Sandbox.activity/2` with `:idle`
      when it takes activity, as a Tuist sandbox pauses on it, else
      `c:Condukt.Sandbox.shutdown/1`, and it starts again on the next call
    * `:before_use` — a function of the sandbox run before a call that
      starts work or touches files reaches it (an exec, a process start, a
      file read, write, edit, glob, or grep), at most once a second, such as
      a one-way sync of the worktree. It runs in the process that keeps the
      machine, so calls that arrive while it runs wait for it, and two never
      run at once. Reading, writing to, stopping, or watching a running
      process does not run it, so a parked command's watcher never syncs
      under the running command.
    * `:owner` — the process the machine lives no longer than: when it
      exits, the machine is let go for good, so an owner that dies without
      `Condukt.Sandbox.shutdown/1` does not leave it running. Defaults to
      the process that calls `Condukt.Sandbox.new/2`. Pass a process that
      outlives the sessions using it, such as the one that starts them, when
      that is not the caller, or `nil` to keep it until
      `Condukt.Sandbox.shutdown/1`.

  A parked command keeps it in use, since its watcher reads it every few
  seconds.
  """

  @behaviour Condukt.Sandbox

  alias Condukt.Sandbox
  alias Condukt.Sandbox.Lazy.Server

  @impl Sandbox
  def init(opts) do
    case Keyword.fetch(opts, :sandbox) do
      {:ok, _spec} -> GenServer.start(Server, Keyword.put_new(opts, :owner, self()))
      :error -> {:error, :missing_sandbox}
    end
  end

  @doc "The started sandbox, starting it when needed."
  def sandbox(%Sandbox{module: __MODULE__, state: pid}), do: GenServer.call(pid, :sandbox, :infinity)

  @impl Sandbox
  def shutdown(pid) do
    GenServer.stop(pid)
  catch
    :exit, _reason -> :ok
  end

  @impl Sandbox
  def cwd(pid), do: with_sandbox(pid, &Sandbox.cwd/1, false)

  @impl Sandbox
  def read_file(pid, path), do: with_sandbox(pid, &Sandbox.read(&1, path))
  @impl Sandbox
  def write_file(pid, path, content), do: with_sandbox(pid, &Sandbox.write(&1, path, content))
  @impl Sandbox
  def edit_file(pid, path, old, new), do: with_sandbox(pid, &Sandbox.edit(&1, path, old, new))
  @impl Sandbox
  def exec(pid, command, opts), do: with_sandbox(pid, &Sandbox.exec(&1, command, opts))
  @impl Sandbox
  def glob(pid, pattern, opts), do: with_sandbox(pid, &Sandbox.glob(&1, pattern, opts))
  @impl Sandbox
  def grep(pid, pattern, opts), do: with_sandbox(pid, &Sandbox.grep(&1, pattern, opts))
  @impl Sandbox
  def list_dir(pid, path), do: with_sandbox(pid, &Sandbox.list_dir(&1, path))
  @impl Sandbox
  def start_process(pid, id, command, opts), do: with_sandbox(pid, &Sandbox.start_process(&1, id, command, opts))
  @impl Sandbox
  def read_process(pid, id, offset, opts), do: with_sandbox(pid, &Sandbox.read_process(&1, id, offset, opts), false)
  @impl Sandbox
  def stop_process(pid, id), do: with_sandbox(pid, &Sandbox.stop_process(&1, id), false)
  @impl Sandbox
  def write_process(pid, id, data, opts), do: with_sandbox(pid, &Sandbox.write_process(&1, id, data, opts), false)
  @impl Sandbox
  def watch_process(pid, id, target), do: with_sandbox(pid, &Sandbox.watch_process(&1, id, target), false)
  @impl Sandbox
  def snapshot(pid, opts), do: with_sandbox(pid, &Sandbox.snapshot(&1, opts), false)
  @impl Sandbox
  def expose_port(pid, port, opts), do: with_sandbox(pid, &Sandbox.expose_port(&1, port, opts), false)

  defp with_sandbox(pid, fun, before_use? \\ true) do
    case GenServer.call(pid, {:use, before_use?}, :infinity) do
      {:ok, sandbox} -> fun.(sandbox)
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule Condukt.Sandbox.Lazy.Server do
  @moduledoc false
  use GenServer

  alias Condukt.Sandbox

  @default_idle_after 600_000
  @sync_every 1_000

  @impl GenServer
  def init(opts) do
    case Keyword.fetch!(opts, :owner) do
      nil -> :ok
      owner -> Process.monitor(owner)
    end

    {:ok,
     %{
       spec: Keyword.fetch!(opts, :sandbox),
       sandbox: nil,
       idle: false,
       idle_after: Keyword.get(opts, :idle_after, @default_idle_after),
       before_use: Keyword.get(opts, :before_use),
       synced_at: nil,
       timer: nil
     }}
  end

  @impl GenServer
  def handle_call(request, _from, state) do
    case started(state) do
      {:ok, state} -> reply(request, %{state | timer: rearm(state)})
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp reply(:sandbox, state), do: {:reply, state.sandbox, state}

  # `before_use` runs here, so a call that arrives while it runs waits for
  # it rather than reaching the machine first, and two never overlap. The
  # second a sync is spared counts from when the last one finished.
  defp reply({:use, before_use?}, state) do
    sync? =
      before_use? and state.before_use != nil and
        (state.synced_at == nil or System.monotonic_time(:millisecond) - state.synced_at >= @sync_every)

    if sync? do
      state.before_use.(state.sandbox)
      {:reply, {:ok, state.sandbox}, %{state | synced_at: System.monotonic_time(:millisecond)}}
    else
      {:reply, {:ok, state.sandbox}, state}
    end
  end

  @impl GenServer
  def handle_info(:idle, %{sandbox: %Sandbox{} = sandbox} = state) do
    if Sandbox.supports?(sandbox, :activity, 2) do
      _ = Sandbox.activity(sandbox, :idle)
      {:noreply, %{state | timer: nil, idle: true}}
    else
      Sandbox.shutdown(sandbox)
      {:noreply, %{state | sandbox: nil, timer: nil, synced_at: nil}}
    end
  end

  # Its owner is gone, so nothing will shut it down: `terminate/2` does.
  def handle_info({:DOWN, _ref, :process, _owner, _reason}, state), do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{sandbox: %Sandbox{} = sandbox}), do: Sandbox.shutdown(sandbox)
  def terminate(_reason, _state), do: :ok

  defp started(%{sandbox: nil} = state) do
    with {:ok, sandbox} <- Sandbox.resolve(state.spec) do
      {:ok, %{state | sandbox: sandbox, idle: false}}
    end
  end

  # Taken again after an idle release on a sandbox that takes activity.
  defp started(%{idle: true} = state) do
    _ = Sandbox.activity(state.sandbox, :active)
    {:ok, %{state | idle: false}}
  end

  defp started(state), do: {:ok, state}

  defp rearm(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    Process.send_after(self(), :idle, state.idle_after)
  end
end
