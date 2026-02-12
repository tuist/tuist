defmodule Cache.MultipartUploads do
  @moduledoc """
  GenServer for managing in-progress multipart uploads.

  Uses ETS for state management to track upload metadata and parts.
  Automatically cleans up abandoned uploads after 5 minutes.
  """

  use GenServer

  alias Cache.Disk
  alias Cache.Module.Disk, as: ModuleDisk

  require Logger

  @table_name :multipart_uploads
  @cleanup_interval_ms 60_000
  @upload_timeout_ms 5 * 60 * 1000
  @max_part_size 10 * 1024 * 1024
  @max_total_size 2 * 1024 * 1024 * 1024

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Start a new multipart upload.

  Returns `{:ok, upload_id}` where upload_id is a UUID string.
  """
  def start_upload(account_handle, project_handle, category, hash, name) do
    GenServer.call(__MODULE__, {:start_upload, account_handle, project_handle, category, hash, name})
  end

  def add_part(upload_id, part_number, temp_file_path, size_bytes) do
    GenServer.call(__MODULE__, {:add_part, upload_id, part_number, temp_file_path, size_bytes})
  end

  @doc """
  Claims the assembly device for a direct sequential write when possible.

  Returns `{:direct_write, device}` when `part_number` matches the next expected
  sequential part and no write is currently in progress, `:buffer` otherwise.
  """
  def claim_sequential_write(upload_id, part_number) do
    GenServer.call(__MODULE__, {:claim_sequential_write, upload_id, part_number})
  end

  @doc """
  Confirms a completed direct write.
  """
  def confirm_write(upload_id, part_number, size_bytes) do
    GenServer.call(__MODULE__, {:confirm_write, upload_id, part_number, size_bytes})
  end

  @doc """
  Releases an in-progress sequential write claim without advancing state.
  """
  def abort_write(upload_id) do
    GenServer.call(__MODULE__, {:abort_write, upload_id})
  end

  @doc """
  Get upload metadata and parts.

  Returns `{:ok, upload_data}` or `{:error, :not_found}`.
  """
  def get_upload(upload_id) do
    GenServer.call(__MODULE__, {:get_upload, upload_id})
  end

  @doc """
  Complete a multipart upload.

  Returns the upload metadata with parts list for assembly and removes it from ETS.
  Does NOT delete temp files - caller handles after assembly.

  Returns `{:ok, upload_data}` or `{:error, :not_found}`.
  """
  def complete_upload(upload_id) do
    GenServer.call(__MODULE__, {:complete_upload, upload_id})
  end

  @doc """
  Abort a multipart upload.

  Cleans up temp files and removes the upload from ETS.
  """
  def abort_upload(upload_id) do
    GenServer.call(__MODULE__, {:abort_upload, upload_id})
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:set, :protected, :named_table])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:start_upload, account_handle, project_handle, category, hash, name}, _from, state) do
    upload_id = UUIDv7.generate()
    assembly_path = ModuleDisk.assembly_path(account_handle, project_handle, category, hash, name, upload_id)

    with :ok <- Disk.ensure_directory(assembly_path),
         {:ok, assembly_device} <- File.open(assembly_path, [:write, :binary]) do
      upload_data = %{
        account_handle: account_handle,
        project_handle: project_handle,
        category: category,
        hash: hash,
        name: name,
        parts: %{},
        total_bytes: 0,
        created_at: DateTime.utc_now(),
        assembly_path: assembly_path,
        assembly_device: assembly_device,
        next_sequential: 1,
        write_in_progress: false
      }

      :ets.insert(@table_name, {upload_id, upload_data})
      {:reply, {:ok, upload_id}, state}
    else
      {:error, reason} ->
        Logger.error("Failed to start multipart upload #{upload_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:add_part, upload_id, part_number, temp_file_path, size_bytes}, _from, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, {:error, :upload_not_found}, state}

      [{^upload_id, upload_data}] ->
        cond do
          size_bytes > @max_part_size ->
            {:reply, {:error, :part_too_large}, state}

          projected_total(upload_data, part_number, size_bytes) > @max_total_size ->
            {:reply, {:error, :total_size_exceeded}, state}

          true ->
            updated_parts = Map.put(upload_data.parts, part_number, %{path: temp_file_path, size: size_bytes})

            updated_data = %{
              upload_data
              | parts: updated_parts,
                total_bytes: projected_total(upload_data, part_number, size_bytes)
            }

            :ets.insert(@table_name, {upload_id, updated_data})
            {:reply, :ok, state}
        end
    end
  end

  @impl true
  def handle_call({:claim_sequential_write, upload_id, part_number}, _from, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, {:error, :upload_not_found}, state}

      [{^upload_id, upload_data}] ->
        if upload_data.next_sequential == part_number and not upload_data.write_in_progress do
          updated_data = %{upload_data | write_in_progress: true}
          :ets.insert(@table_name, {upload_id, updated_data})
          {:reply, {:direct_write, upload_data.assembly_device}, state}
        else
          {:reply, :buffer, state}
        end
    end
  end

  @impl true
  def handle_call({:confirm_write, upload_id, part_number, size_bytes}, _from, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, {:error, :upload_not_found}, state}

      [{^upload_id, upload_data}] ->
        part_data = %{size: size_bytes, written: true}

        updated_data = %{
          upload_data
          | parts: Map.put(upload_data.parts, part_number, part_data),
            total_bytes: projected_total(upload_data, part_number, size_bytes),
            next_sequential: max(upload_data.next_sequential, part_number + 1),
            write_in_progress: false
        }

        :ets.insert(@table_name, {upload_id, updated_data})
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:abort_write, upload_id}, _from, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, {:error, :upload_not_found}, state}

      [{^upload_id, upload_data}] ->
        updated_data = %{upload_data | write_in_progress: false}
        :ets.insert(@table_name, {upload_id, updated_data})
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:get_upload, upload_id}, _from, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] -> {:reply, {:error, :not_found}, state}
      [{^upload_id, upload_data}] -> {:reply, {:ok, upload_data}, state}
    end
  end

  @impl true
  def handle_call({:complete_upload, upload_id}, _from, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, {:error, :not_found}, state}

      [{^upload_id, upload_data}] ->
        close_assembly_device(upload_data)
        :ets.delete(@table_name, upload_id)
        {:reply, {:ok, upload_data}, state}
    end
  end

  @impl true
  def handle_call({:abort_upload, upload_id}, _from, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, :ok, state}

      [{^upload_id, upload_data}] ->
        close_assembly_device(upload_data)
        File.rm(upload_data.assembly_path)
        cleanup_temp_files(upload_data.parts)
        :ets.delete(@table_name, upload_id)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info(:cleanup_abandoned, state) do
    now = DateTime.utc_now()

    :ets.foldl(
      fn {upload_id, upload_data}, _acc ->
        age_ms = DateTime.diff(now, upload_data.created_at, :millisecond)

        if age_ms > @upload_timeout_ms do
          Logger.info("Cleaning up abandoned multipart upload #{upload_id}")
          close_assembly_device(upload_data)
          File.rm(upload_data.assembly_path)
          cleanup_temp_files(upload_data.parts)
          :ets.delete(@table_name, upload_id)
        end

        nil
      end,
      nil,
      @table_name
    )

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_abandoned, @cleanup_interval_ms)
  end

  defp cleanup_temp_files(parts) do
    Enum.each(parts, fn
      {_part_number, %{path: path}} -> File.rm(path)
      _ -> :ok
    end)
  end

  defp close_assembly_device(upload_data) do
    case upload_data do
      %{assembly_device: nil} -> :ok
      %{assembly_device: device} -> File.close(device)
      _ -> :ok
    end
  end

  defp projected_total(upload_data, part_number, incoming_size) do
    replaced_size =
      upload_data.parts
      |> Map.get(part_number, %{})
      |> Map.get(:size, 0)

    upload_data.total_bytes - replaced_size + incoming_size
  end
end
