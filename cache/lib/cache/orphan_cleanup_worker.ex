defmodule Cache.OrphanCleanupWorker do
  @moduledoc """
  Oban worker that incrementally walks the disk storage tree, detects files
  with no matching cache_artifacts row, and deletes them.

  Orphans occur because writing a file to disk and registering its metadata
  in the cache_artifacts table are two separate, non-atomic operations.
  In the upload path (CAS, module cache, Gradle), `Disk.put/4` writes the
  file first, and `CacheArtifacts.track_artifact_access/1` enqueues a
  metadata record to an ETS buffer that periodically flushes to SQLite.
  If the process crashes, the VM restarts, or the buffer fails to flush
  between those two steps, the file is left on disk with no metadata row.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.OrphanScanCursor

  require Logger

  @default_max_dirs 50
  @min_age_seconds 3600

  @impl Oban.Worker
  def perform(_job) do
    storage_dir = Disk.storage_dir()
    max_dirs = Application.get_env(:cache, :orphan_scan_max_dirs_per_run, @default_max_dirs)
    cursor = OrphanScanCursor.get_cursor()
    cursor_path = if cursor, do: cursor.cursor_path

    {new_cursor, summary} = scan(storage_dir, cursor_path, max_dirs)

    case new_cursor do
      nil -> OrphanScanCursor.reset_cursor()
      path -> OrphanScanCursor.update_cursor(path)
    end

    log_summary(summary)
    :ok
  end

  defp scan(storage_dir, cursor_path, max_dirs) do
    leaf_dirs =
      storage_dir
      |> find_leaf_dirs()
      |> Enum.map(&Path.relative_to(&1, storage_dir))
      |> Enum.sort()

    dirs_after_cursor =
      Enum.filter(leaf_dirs, fn relative_dir ->
        is_nil(cursor_path) or relative_dir > cursor_path
      end)

    dirs_to_process = Enum.take(dirs_after_cursor, max_dirs)

    {all_keys, files_checked} =
      Enum.reduce(dirs_to_process, {[], 0}, fn relative_dir, {acc_keys, acc_files_checked} ->
        dir = Path.join(storage_dir, relative_dir)
        {keys, checked} = keys_for_dir(dir, storage_dir)
        {acc_keys ++ keys, acc_files_checked + checked}
      end)

    existing_keys = CacheArtifacts.existing_keys(all_keys)
    orphan_keys = all_keys -- existing_keys

    {orphans_deleted, bytes_freed} = delete_orphans(orphan_keys, storage_dir)

    new_cursor =
      if length(dirs_to_process) < max_dirs do
        nil
      else
        List.last(dirs_to_process)
      end

    summary = %{
      dirs_scanned: length(dirs_to_process),
      files_checked: files_checked,
      orphans_deleted: orphans_deleted,
      bytes_freed: bytes_freed
    }

    {new_cursor, summary}
  end

  defp find_leaf_dirs(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        full_paths = Enum.map(entries, &Path.join(dir, &1))
        subdirs = Enum.filter(full_paths, &File.dir?/1)
        files = Enum.filter(full_paths, &File.regular?/1)

        child_leaves = Enum.flat_map(subdirs, &find_leaf_dirs/1)

        if files == [] do
          child_leaves
        else
          [dir | child_leaves]
        end

      {:error, _} ->
        []
    end
  end

  defp keys_for_dir(dir, storage_dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.filter(&File.regular?/1)
        |> Enum.reduce({[], 0}, fn path, {acc_keys, acc_count} ->
          filename = Path.basename(path)

          if tmp_file?(filename) or not old_enough?(path) do
            {acc_keys, acc_count + 1}
          else
            {[Path.relative_to(path, storage_dir) | acc_keys], acc_count + 1}
          end
        end)

      {:error, _} ->
        {[], 0}
    end
  end

  defp delete_orphans(orphan_keys, storage_dir) do
    Enum.reduce(orphan_keys, {0, 0}, fn key, {deleted_count, freed_bytes} ->
      path = Path.join(storage_dir, key)
      size = file_size(path)

      case File.rm(path) do
        :ok ->
          {deleted_count + 1, freed_bytes + size}

        {:error, :enoent} ->
          {deleted_count, freed_bytes}

        {:error, reason} ->
          Logger.warning("Failed to delete orphan #{key}: #{inspect(reason)}")
          {deleted_count, freed_bytes}
      end
    end)
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, _} -> 0
    end
  end

  defp old_enough?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{mtime: mtime}} ->
        mtime_seconds = mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
        now_seconds = System.os_time(:second)
        now_seconds - mtime_seconds >= @min_age_seconds

      {:error, _} ->
        false
    end
  end

  defp tmp_file?(filename) do
    String.starts_with?(filename, ".tmp.") or String.starts_with?(filename, ".cache-upload-")
  end

  defp log_summary(%{orphans_deleted: 0, dirs_scanned: dirs}) do
    Logger.info("Orphan scan: scanned #{dirs} directories, no orphans found")
  end

  defp log_summary(%{orphans_deleted: count, bytes_freed: bytes, dirs_scanned: dirs, files_checked: files}) do
    Logger.info(
      "Orphan scan: scanned #{dirs} directories, checked #{files} files, deleted #{count} orphans freeing #{format_bytes(bytes)}"
    )
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 2)} KB"
  defp format_bytes(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 2)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"
end
