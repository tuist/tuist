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

  @doc """
  Registers a buffered part (written to a temp file).

  Returns `{:error, :part_already_written}` if the part was already directly written
  to the assembly file and cannot be replaced.
  """
  def add_part(upload_id, part_number, temp_file_path, size_bytes) do
    GenServer.call(__MODULE__, {:add_part, upload_id, part_number, temp_file_path, size_bytes})
  end

  @doc """
  Claims the assembly file for a direct sequential write when possible.

  Returns `{:direct_write, path, offset}` when `part_number` matches the next expected
  sequential part and no write is currently in progress, `:buffer` otherwise.

  The caller is expected to open the file at `path`, seek to `offset`, and write
  directly using `:raw` mode for maximum throughput.

  The caller process is monitored; if it dies before calling `confirm_write/3` or
  `abort_write/1`, the lock is automatically released and partial bytes are truncated.
  """
  def claim_sequential_write(upload_id, part_number) do
    GenServer.call(__MODULE__, {:claim_sequential_write, upload_id, part_number})
  end

  @doc """
  Confirms a completed direct write and enforces total size limits.

  Returns `:ok` on success, `{:error, :total_size_exceeded}` if the write pushed
  total bytes over the limit, or `{:error, :upload_not_found}`.
  """
  def confirm_write(upload_id, part_number, size_bytes) do
    GenServer.call(__MODULE__, {:confirm_write, upload_id, part_number, size_bytes})
  end

  @doc """
  Releases an in-progress sequential write claim without advancing state.
  Truncates the assembly file back to the offset recorded at claim time.
  """
  def abort_write(upload_id) do
    GenServer.call(__MODULE__, {:abort_write, upload_id})
  end

  @doc """
  Get upload metadata and parts.

  Reads directly from ETS (the table is `:protected`, so any process can read).
  Returns `{:ok, upload_data}` or `{:error, :not_found}`.
  """
  def get_upload(upload_id) do
    case :ets.lookup(@table_name, upload_id) do
      [{^upload_id, upload_data}] -> {:ok, upload_data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Complete a multipart upload.

  Returns the upload metadata with parts list for assembly and removes it from ETS.
  Does NOT delete temp files - caller handles after assembly.

  Returns `{:error, :write_in_progress}` if a direct write is currently in-flight.
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
    {:ok, %{table: table, monitors: %{}}}
  end

  @impl true
  def handle_call({:start_upload, account_handle, project_handle, category, hash, name}, _from, state) do
    upload_id = UUIDv7.generate()
    assembly_path = ModuleDisk.assembly_path(account_handle, project_handle, category, hash, name, upload_id)

    case Disk.ensure_directory(assembly_path) do
      :ok ->
        now = DateTime.utc_now()

        upload_data = %{
          account_handle: account_handle,
          project_handle: project_handle,
          category: category,
          hash: hash,
          name: name,
          parts: %{},
          total_bytes: 0,
          created_at: now,
          last_activity_at: now,
          assembly_path: assembly_path,
          assembly_offset: 0,
          next_sequential: 1,
          write_in_progress: nil
        }

        :ets.insert(@table_name, {upload_id, upload_data})
        {:reply, {:ok, upload_id}, state}

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
        case validate_add_part(upload_data, part_number, size_bytes) do
          :ok ->
            existing_part = Map.get(upload_data.parts, part_number)
            updated_parts = Map.put(upload_data.parts, part_number, %{path: temp_file_path, size: size_bytes})

            updated_data = %{
              upload_data
              | parts: updated_parts,
                total_bytes: projected_total(upload_data, part_number, size_bytes),
                last_activity_at: DateTime.utc_now()
            }

            :ets.insert(@table_name, {upload_id, updated_data})
            maybe_cleanup_old_part_async(existing_part)
            {:reply, :ok, state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:claim_sequential_write, upload_id, part_number}, {caller_pid, _tag}, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, {:error, :upload_not_found}, state}

      [{^upload_id, upload_data}] ->
        part_already_buffered = Map.has_key?(upload_data.parts, part_number)

        has_headroom = upload_data.total_bytes < @max_total_size

        if upload_data.next_sequential == part_number and upload_data.write_in_progress == nil and
             not part_already_buffered and has_headroom do
          offset = upload_data.assembly_offset
          ref = Process.monitor(caller_pid)

          updated_data = %{
            upload_data
            | write_in_progress: %{pid: caller_pid, ref: ref, offset: offset, part_number: part_number},
              last_activity_at: DateTime.utc_now()
          }

          :ets.insert(@table_name, {upload_id, updated_data})
          monitors = Map.put(state.monitors, ref, upload_id)
          {:reply, {:direct_write, upload_data.assembly_path, offset}, %{state | monitors: monitors}}
        else
          {:reply, :buffer, state}
        end
    end
  end

  @impl true
  def handle_call({:confirm_write, upload_id, part_number, size_bytes}, {caller_pid, _tag}, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, {:error, :upload_not_found}, state}

      [{^upload_id, %{write_in_progress: %{pid: ^caller_pid, part_number: ^part_number}} = upload_data}] ->
        state = demonitor_write(upload_data, state)
        new_total = projected_total(upload_data, part_number, size_bytes)

        if new_total > @max_total_size do
          truncate_to_offset(upload_data)

          updated_data = %{
            upload_data
            | write_in_progress: nil,
              last_activity_at: DateTime.utc_now()
          }

          :ets.insert(@table_name, {upload_id, updated_data})
          {:reply, {:error, :total_size_exceeded}, state}
        else
          part_data = %{size: size_bytes, written: true}

          updated_data = %{
            upload_data
            | parts: Map.put(upload_data.parts, part_number, part_data),
              total_bytes: new_total,
              assembly_offset: upload_data.assembly_offset + size_bytes,
              next_sequential: max(upload_data.next_sequential, part_number + 1),
              write_in_progress: nil,
              last_activity_at: DateTime.utc_now()
          }

          :ets.insert(@table_name, {upload_id, updated_data})
          {:reply, :ok, state}
        end

      [{^upload_id, _upload_data}] ->
        {:reply, {:error, :not_claimant}, state}
    end
  end

  @impl true
  def handle_call({:abort_write, upload_id}, {caller_pid, _tag}, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, {:error, :upload_not_found}, state}

      [{^upload_id, %{write_in_progress: %{pid: ^caller_pid}} = upload_data}] ->
        state = demonitor_write(upload_data, state)
        truncate_to_offset(upload_data)

        updated_data = %{
          upload_data
          | write_in_progress: nil,
            last_activity_at: DateTime.utc_now()
        }

        :ets.insert(@table_name, {upload_id, updated_data})
        {:reply, :ok, state}

      [{^upload_id, _upload_data}] ->
        {:reply, {:error, :not_claimant}, state}
    end
  end

  @impl true
  def handle_call({:complete_upload, upload_id}, _from, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, {:error, :not_found}, state}

      [{^upload_id, upload_data}] ->
        if upload_data.write_in_progress == nil do
          :ets.delete(@table_name, upload_id)
          {:reply, {:ok, upload_data}, state}
        else
          {:reply, {:error, :write_in_progress}, state}
        end
    end
  end

  @impl true
  def handle_call({:abort_upload, upload_id}, _from, state) do
    case :ets.lookup(@table_name, upload_id) do
      [] ->
        {:reply, :ok, state}

      [{^upload_id, upload_data}] ->
        state = demonitor_write(upload_data, state)
        File.rm(upload_data.assembly_path)
        cleanup_temp_files(upload_data.parts)
        :ets.delete(@table_name, upload_id)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {upload_id, monitors} ->
        state = %{state | monitors: monitors}

        case :ets.lookup(@table_name, upload_id) do
          [{^upload_id, upload_data}] when upload_data.write_in_progress != nil ->
            Logger.warning("Writer process died during direct write for upload #{upload_id}, releasing lock")

            truncate_to_offset(upload_data)

            updated_data = %{
              upload_data
              | write_in_progress: nil,
                last_activity_at: DateTime.utc_now()
            }

            :ets.insert(@table_name, {upload_id, updated_data})
            {:noreply, state}

          _ ->
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(:cleanup_abandoned, state) do
    now = DateTime.utc_now()

    {abandoned, state} =
      :ets.foldl(
        fn {upload_id, upload_data}, {acc_abandoned, acc_state} ->
          age_ms = DateTime.diff(now, upload_data.last_activity_at, :millisecond)

          if age_ms > @upload_timeout_ms and upload_data.write_in_progress == nil do
            acc_state = demonitor_write(upload_data, acc_state)
            :ets.delete(@table_name, upload_id)
            {[{upload_id, upload_data} | acc_abandoned], acc_state}
          else
            {acc_abandoned, acc_state}
          end
        end,
        {[], state},
        @table_name
      )

    if abandoned != [] do
      Task.start(fn ->
        Enum.each(abandoned, fn {upload_id, upload_data} ->
          Logger.info("Cleaning up abandoned multipart upload #{upload_id}")
          File.rm(upload_data.assembly_path)
          cleanup_temp_files(upload_data.parts)
        end)
      end)
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_abandoned, @cleanup_interval_ms)
  end

  defp truncate_to_offset(%{write_in_progress: %{offset: offset}, assembly_path: path}) do
    case :file.open(String.to_charlist(path), [:write, :read, :binary, :raw]) do
      {:ok, fd} ->
        :file.position(fd, offset)
        :file.truncate(fd)
        :file.close(fd)

      _ ->
        :ok
    end
  end

  defp truncate_to_offset(_upload_data), do: :ok

  defp demonitor_write(%{write_in_progress: %{ref: ref}}, state) do
    Process.demonitor(ref, [:flush])
    %{state | monitors: Map.delete(state.monitors, ref)}
  end

  defp demonitor_write(_upload_data, state), do: state

  defp validate_add_part(upload_data, part_number, size_bytes) do
    existing_part = Map.get(upload_data.parts, part_number)

    write_in_progress_for_part =
      upload_data.write_in_progress != nil and upload_data.write_in_progress.part_number == part_number

    cond do
      write_in_progress_for_part -> {:error, :part_write_in_progress}
      existing_part != nil and Map.get(existing_part, :written) == true -> {:error, :part_already_written}
      size_bytes > @max_part_size -> {:error, :part_too_large}
      projected_total(upload_data, part_number, size_bytes) > @max_total_size -> {:error, :total_size_exceeded}
      true -> :ok
    end
  end

  defp maybe_cleanup_old_part_async(%{path: old_path}), do: Task.start(fn -> File.rm(old_path) end)
  defp maybe_cleanup_old_part_async(_), do: :ok

  defp cleanup_temp_files(parts) do
    Enum.each(parts, fn
      {_part_number, %{path: path}} -> File.rm(path)
      _ -> :ok
    end)
  end

  defp projected_total(upload_data, part_number, incoming_size) do
    replaced_size =
      upload_data.parts
      |> Map.get(part_number, %{})
      |> Map.get(:size, 0)

    upload_data.total_bytes - replaced_size + incoming_size
  end
end
