defmodule Tuist.XcresultDrain do
  @moduledoc """
  Stops the local processor queue before tart-kubelet tears down its VM.

  The per-VM status share carries the Pod UID as a request and acknowledgement.
  No distributed Erlang or server-side Oban notification is involved. Once
  requested, the queue remains stopped until the VM is deleted.
  """
  use GenServer

  require Logger

  @directory "/Volumes/My Shared Files/status"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def requested?(directory \\ @directory) do
    match?({:ok, _}, request(directory))
  end

  @impl true
  def init(opts) do
    state = %{directory: Keyword.get(opts, :directory, @directory), stopped: false, stopping: false}
    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = poll(state)
    Process.send_after(self(), :poll, 1_000)
    {:noreply, state}
  end

  defp poll(state) do
    case request(state.directory) do
      {:ok, uid} -> drain(state, uid)
      :none -> resume_if_serving(state)
      :invalid -> state
    end
  rescue
    error ->
      Logger.warning("Xcresult drain failed: #{Exception.message(error)}")
      state
  catch
    :exit, reason ->
      Logger.warning("Xcresult drain unavailable: #{inspect(reason)}")
      state
  end

  defp resume_if_serving(%{stopped: false, stopping: false} = state) do
    # The configured queue always starts paused, including an Oban-only
    # supervisor restart. Only this local process can release it while the
    # durable termination request is absent. The serving marker is written
    # before the request is read again, so tart-kubelet, which reads the marker
    # after writing its request, tears down a VM without one immediately.
    if match?(%{paused: true}, Oban.check_queue(queue: :process_xcresult)) do
      File.write!(Path.join(state.directory, "serving"), "")

      if request(state.directory) == :none do
        :ok = Oban.resume_queue(queue: :process_xcresult, local_only: true)
      end
    end

    state
  end

  defp resume_if_serving(state), do: state

  defp drain(%{stopped: true} = state, uid) do
    acknowledge(state.directory, uid)
    state
  end

  defp drain(%{stopping: true} = state, uid) do
    # stop_queue broadcasts asynchronously. Wait for the queue supervisor to
    # disappear, not merely for the call to return :ok or a producer to restart.
    if is_nil(Oban.Registry.whereis(Oban, {:queue, "process_xcresult"})) do
      acknowledge(state.directory, uid)
      %{state | stopped: true}
    else
      state
    end
  end

  defp drain(state, _uid) do
    :ok = Oban.pause_queue(queue: :process_xcresult, local_only: true)

    case Oban.check_queue(queue: :process_xcresult) do
      %{paused: true, running: []} ->
        # Removing the local queue also prevents a producer restart from
        # taking another job after the acknowledgement was written.
        :ok = Oban.stop_queue(queue: :process_xcresult, local_only: true)
        %{state | stopping: true}

      _ ->
        state
    end
  end

  defp request(directory) do
    case File.read(Path.join(directory, "drain-request")) do
      {:ok, uid} ->
        if Regex.match?(~r/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\n\z/, uid), do: {:ok, uid}, else: :invalid

      {:error, :enoent} ->
        :none

      _ ->
        :invalid
    end
  end

  defp acknowledge(directory, uid) do
    temporary = Path.join(directory, "drain-complete.tmp")
    File.write!(temporary, uid)
    File.rename!(temporary, Path.join(directory, "drain-complete"))
  end
end
