defmodule Runner.Runner.VMWarmer do
  @moduledoc """
  Maintains a single warm VM ready for immediate job execution.

  This GenServer warms exactly one VM at a time. When the runner starts,
  it begins booting a VM. When a job acquires that VM, no new VM is started
  until the current job completes and releases the VM.

  ## Lifecycle

  1. On startup, begins booting a single VM
  2. When `acquire/0` is called, returns the warm VM's container_id
  3. When `release/1` is called (job finished), stops that VM and starts warming a new one
  4. Only one VM exists at any time

  ## Usage

      # Start the warmer (typically done by runner start)
      {:ok, _pid} = VMWarmer.start_link(opts)

      # Acquire a warm VM for a job (returns container_id for use with curie commands)
      {:ok, container_id} = VMWarmer.acquire()

      # Release the VM after job completion (stops it and starts warming next one)
      :ok = VMWarmer.release(container_id)
  """

  use GenServer

  require Logger

  alias Runner.Runner.VM

  @default_vm_image "ghcr.io/tuist/macos:26.1-xcode-26.1.1"

  defstruct [
    :warm_vm,        # Full vm_info map from VM.start_ephemeral/2 | nil
    :acquired_vms,   # Map of container_id => vm_info for VMs currently in use
    :warming_task,   # {task_ref, from} or task_ref or nil
    :warming_vm_info, # vm_info of VM currently being warmed (for cleanup on shutdown)
    :vm_opts,
    :counter
  ]

  # Client API

  @doc """
  Starts the VM warmer process.

  ## Options
    - `:image` - VM image to use
    - `:ssh_user` - SSH username
    - `:ssh_key_path` - Path to SSH private key
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Acquires a warm VM for job execution.

  Returns immediately if a warm VM is available, otherwise waits for one to boot.
  Automatically starts warming the next VM in the background.
  """
  @spec acquire(timeout()) :: {:ok, String.t()} | {:error, term()}
  def acquire(timeout \\ 180_000) do
    GenServer.call(__MODULE__, :acquire, timeout)
  end

  @doc """
  Releases a VM after job completion.

  Stops and cleans up the VM. The warmer will already have a new VM ready or warming.
  Takes the container_id returned from acquire/0.
  """
  @spec release(String.t()) :: :ok
  def release(container_id) do
    GenServer.cast(__MODULE__, {:release, container_id})
  end

  @doc """
  Returns the current status of the warmer.
  """
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Stops the warmer and cleans up any VMs.
  """
  @spec stop() :: :ok
  def stop do
    GenServer.stop(__MODULE__, :normal)
  end

  # Server callbacks

  @impl GenServer
  def init(opts) do
    # Trap exits so terminate/2 is called on shutdown
    Process.flag(:trap_exit, true)

    vm_opts = [
      image: Keyword.get(opts, :image, vm_image()),
      ssh_user: Keyword.get(opts, :ssh_user, ssh_user()),
      ssh_key_path: Keyword.get(opts, :ssh_key_path, ssh_key_path()),
      no_display: true
    ]

    state = %__MODULE__{
      warm_vm: nil,
      acquired_vms: %{},
      warming_task: nil,
      warming_vm_info: nil,
      vm_opts: vm_opts,
      counter: 0
    }

    # Check if Curie is available before starting
    case VM.check_curie_available() do
      :ok ->
        Logger.info("VMWarmer starting, beginning to warm first VM...")
        {:ok, state, {:continue, :start_warming}}

      {:error, :curie_not_found} ->
        Logger.warning("VMWarmer: Curie not found, VM warming disabled")
        {:ok, state}
    end
  end

  @impl GenServer
  def handle_continue(:start_warming, state) do
    {:noreply, start_warming_vm(state)}
  end

  @impl GenServer
  def handle_call(:acquire, from, %{warm_vm: nil, warming_task: nil} = state) do
    # No VM available and none warming - start one and wait
    Logger.info("VMWarmer: No VM available, starting one now...")
    state = start_warming_vm(state)
    # Re-enqueue this call to be handled when warming completes
    {:noreply, %{state | warming_task: {state.warming_task, from}}}
  end

  def handle_call(:acquire, from, %{warm_vm: nil, warming_task: task} = state) when not is_nil(task) do
    # VM is currently warming, wait for it
    Logger.info("VMWarmer: VM is warming, waiting...")
    {:noreply, %{state | warming_task: {task, from}}}
  end

  def handle_call(:acquire, _from, %{warm_vm: vm_info} = state) when not is_nil(vm_info) do
    # We have a warm VM ready!
    Logger.info("VMWarmer: Providing warm VM '#{vm_info.container_name}' (#{vm_info.container_id})")

    # Track the acquired VM so we can properly clean it up on release
    new_acquired_vms = Map.put(state.acquired_vms, vm_info.container_id, vm_info)

    # Don't start warming another VM - only warm one at a time
    new_state =
      state
      |> Map.put(:warm_vm, nil)
      |> Map.put(:acquired_vms, new_acquired_vms)

    # Return container_id since that's what curie commands need
    {:reply, {:ok, vm_info.container_id}, new_state}
  end

  def handle_call(:status, _from, state) do
    status = %{
      warm_vm: if(state.warm_vm, do: state.warm_vm.container_id, else: nil),
      warm_vm_name: if(state.warm_vm, do: state.warm_vm.container_name, else: nil),
      is_warming: state.warming_task != nil,
      total_vms_created: state.counter,
      vm_image: state.vm_opts[:image]
    }
    {:reply, status, state}
  end

  @impl GenServer
  def handle_cast({:release, container_id}, state) do
    Logger.info("VMWarmer: Releasing VM '#{container_id}'")

    # Get the full vm_info from our acquired_vms map
    vm_info = Map.get(state.acquired_vms, container_id)

    # Stop the VM in a separate task to not block
    Task.start(fn ->
      if vm_info do
        # Use stop_vm which kills the OS process and cleans up container
        case VM.stop_vm(vm_info) do
          :ok ->
            Logger.info("VMWarmer: VM '#{container_id}' stopped with process cleanup")

          {:error, reason} ->
            Logger.warning("VMWarmer: Failed to stop VM '#{container_id}': #{inspect(reason)}")
        end
      else
        # Fallback to just container cleanup if we don't have vm_info
        Logger.warning("VMWarmer: No vm_info found for '#{container_id}', using basic cleanup")
        VM.stop(container_id)
      end
    end)

    # Remove from acquired_vms
    new_acquired_vms = Map.delete(state.acquired_vms, container_id)

    # Start warming a new VM for the next job (if not already warming)
    new_state =
      state
      |> Map.put(:acquired_vms, new_acquired_vms)

    new_state = if new_state.warm_vm == nil and new_state.warming_task == nil do
      start_warming_vm(new_state)
    else
      new_state
    end

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({ref, {:ok, vm_info}}, state) when is_reference(ref) and is_map(vm_info) do
    # Warming task completed successfully
    Process.demonitor(ref, [:flush])

    Logger.info("VMWarmer: VM '#{vm_info.container_name}' (#{vm_info.container_id}) is warm and ready")

    case state.warming_task do
      {_task_ref, waiting_from} when not is_nil(waiting_from) ->
        # Someone was waiting for this VM - return container_id
        GenServer.reply(waiting_from, {:ok, vm_info.container_id})
        # Track the acquired VM so we can properly clean it up on release
        new_acquired_vms = Map.put(state.acquired_vms, vm_info.container_id, vm_info)
        # Don't start warming another VM - only warm one at a time
        new_state =
          state
          |> Map.put(:warm_vm, nil)
          |> Map.put(:warming_task, nil)
          |> Map.put(:warming_vm_info, nil)
          |> Map.put(:acquired_vms, new_acquired_vms)
        {:noreply, new_state}

      _ ->
        # No one waiting, store as warm VM (full vm_info)
        {:noreply, %{state | warm_vm: vm_info, warming_task: nil, warming_vm_info: nil}}
    end
  end

  def handle_info({ref, {:error, reason}}, state) when is_reference(ref) do
    # Warming task failed
    Process.demonitor(ref, [:flush])

    Logger.error("VMWarmer: Failed to warm VM: #{inspect(reason)}")

    case state.warming_task do
      {_task_ref, waiting_from} when not is_nil(waiting_from) ->
        # Someone was waiting - reply with error
        GenServer.reply(waiting_from, {:error, reason})
        # Try again
        new_state =
          state
          |> Map.put(:warming_task, nil)
          |> Map.put(:warming_vm_info, nil)
          |> start_warming_vm()
        {:noreply, new_state}

      _ ->
        # No one waiting, try again after a delay
        Process.send_after(self(), :retry_warming, 5_000)
        {:noreply, %{state | warming_task: nil, warming_vm_info: nil}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Task crashed
    Logger.error("VMWarmer: Warming task crashed: #{inspect(reason)}")

    # Clean up the warming VM if we have its info
    if state.warming_vm_info do
      Logger.info("VMWarmer: Cleaning up crashed warming VM '#{state.warming_vm_info.container_id}'")
      VM.stop_vm(state.warming_vm_info)
    end

    case state.warming_task do
      {^ref, waiting_from} when not is_nil(waiting_from) ->
        GenServer.reply(waiting_from, {:error, {:warming_crashed, reason}})
        new_state =
          state
          |> Map.put(:warming_task, nil)
          |> Map.put(:warming_vm_info, nil)
          |> start_warming_vm()
        {:noreply, new_state}

      {^ref, nil} ->
        # Retry warming
        Process.send_after(self(), :retry_warming, 5_000)
        {:noreply, %{state | warming_task: nil, warming_vm_info: nil}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(:retry_warming, %{warming_task: nil} = state) do
    Logger.info("VMWarmer: Retrying to warm a VM...")
    {:noreply, start_warming_vm(state)}
  end

  def handle_info(:retry_warming, state) do
    # Already warming, ignore
    {:noreply, state}
  end

  def handle_info({:warming_vm_started, vm_info}, state) do
    # Track the VM being warmed so we can clean it up on shutdown
    Logger.debug("VMWarmer: Tracking warming VM '#{vm_info.container_id}' for cleanup")
    {:noreply, %{state | warming_vm_info: vm_info}}
  end

  def handle_info(msg, state) do
    Logger.debug("VMWarmer: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.info("VMWarmer terminating: #{inspect(reason)}")

    # Clean up warm VM if any (with process cleanup)
    if state.warm_vm do
      Logger.info("VMWarmer: Stopping warm VM '#{state.warm_vm.container_name}' (#{state.warm_vm.container_id})")
      VM.stop_vm(state.warm_vm)
    end

    # Clean up VM currently being warmed (if any)
    if state.warming_vm_info do
      Logger.info("VMWarmer: Stopping warming VM '#{state.warming_vm_info.container_id}'")
      VM.stop_vm(state.warming_vm_info)
    end

    # Clean up any acquired VMs that weren't released
    for {container_id, vm_info} <- state.acquired_vms do
      Logger.info("VMWarmer: Stopping acquired VM '#{container_id}'")
      VM.stop_vm(vm_info)
    end

    :ok
  end

  # Private functions

  defp start_warming_vm(state) do
    counter = state.counter + 1
    container_name = "tuist-warm-#{counter}"
    parent = self()

    Logger.info("VMWarmer: Starting to warm VM '#{container_name}'...")

    task =
      Task.async(fn ->
        warm_vm(container_name, state.vm_opts, parent)
      end)

    %{state | warming_task: task.ref, counter: counter, warming_vm_info: nil}
  end

  defp warm_vm(container_name, vm_opts, parent) do
    case VM.start_ephemeral(container_name, vm_opts) do
      {:ok, vm_info} ->
        # Send vm_info to parent immediately so it can be tracked for cleanup
        send(parent, {:warming_vm_started, vm_info})

        case VM.wait_for_ready(vm_info.container_id, vm_opts) do
          :ok -> {:ok, vm_info}
          {:error, reason} ->
            # Clean up the VM that failed to become ready
            VM.stop_vm(vm_info)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Configuration helpers

  defp vm_image do
    System.get_env("VM_IMAGE", @default_vm_image)
  end

  defp ssh_user do
    System.get_env("VM_SSH_USER", "tuist")
  end

  defp ssh_key_path do
    System.get_env("VM_SSH_KEY_PATH", "~/.ssh/id_ed25519")
  end
end
