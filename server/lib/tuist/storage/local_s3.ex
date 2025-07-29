defmodule Tuist.Storage.LocalS3 do
  @moduledoc """
  Manages the lifecycle of local storage directories in development.
  Ensures cleanup on application termination.
  """

  use GenServer

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    Process.flag(:trap_exit, true)

    storage_dir = get_storage_dir()
    File.mkdir_p!(storage_dir)

    Logger.info("Local storage directory created at: #{storage_dir}")

    {:ok, %{storage_dir: storage_dir}}
  end

  def terminate(_reason, %{storage_dir: storage_dir}) do
    if File.exists?(storage_dir) do
      Logger.info("Cleaning up local storage directory: #{storage_dir}")
      File.rm_rf!(storage_dir)
    end

    :ok
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  @project_root [__DIR__, "..", "..", ".."] |> Path.join() |> Path.expand()

  def get_storage_dir do
    timestamp = DateTime.to_unix(DateTime.utc_now(), :millisecond)
    Path.join([@project_root, "tmp", "local_storage_#{timestamp}"])
  end

  @doc """
  Get the current storage directory path
  """
  def storage_directory do
    case Process.whereis(__MODULE__) do
      nil ->
        get_storage_dir()

      pid ->
        GenServer.call(pid, :get_storage_dir)
    end
  end

  def handle_call(:get_storage_dir, _from, %{storage_dir: storage_dir} = state) do
    {:reply, storage_dir, state}
  end
end
