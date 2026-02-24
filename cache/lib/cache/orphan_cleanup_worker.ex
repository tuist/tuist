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
  alias Cache.OrphanScanCursors

  require Logger

  @default_max_dirs 50
  @min_age_seconds 3600

  @impl Oban.Worker
  def perform(_job) do
    storage_dir = Disk.storage_dir()
    max_dirs = Application.get_env(:cache, :orphan_scan_max_dirs_per_run, @default_max_dirs)
    cursor = OrphanScanCursors.get_cursor()
    cursor_path = if cursor, do: cursor.cursor_path

    {new_cursor, summary} = scan(storage_dir, cursor_path, max_dirs)

    case new_cursor do
      nil -> OrphanScanCursors.reset_cursor()
      path -> OrphanScanCursors.update_cursor(path)
    end

    log_summary(summary)
    :ok
  end

  defp scan(storage_dir, cursor_path, max_dirs) do
    dirs_to_process =
      storage_dir
      |> stream_leaf_dirs(cursor_path)
      |> Stream.map(&Path.relative_to(&1, storage_dir))
      |> Stream.filter(fn dir -> is_nil(cursor_path) or dir > cursor_path end)
      |> Enum.take(max_dirs)

    dirs_count = length(dirs_to_process)
    now = System.os_time(:second)

    {all_entries, files_checked} =
      Enum.reduce(dirs_to_process, {[], 0}, fn relative_dir, {acc_entries, acc_files_checked} ->
        dir = Path.join(storage_dir, relative_dir)
        {entries, checked} = keys_for_dir(dir, storage_dir, now)
        {entries ++ acc_entries, acc_files_checked + checked}
      end)

    all_keys = Enum.map(all_entries, fn {key, _size} -> key end)
    existing_set = MapSet.new(CacheArtifacts.existing_keys(all_keys))

    orphan_entries =
      Enum.reject(all_entries, fn {key, _size} -> MapSet.member?(existing_set, key) end)

    {orphans_deleted, bytes_freed} = delete_orphans(orphan_entries, storage_dir)

    new_cursor =
      if dirs_count < max_dirs do
        nil
      else
        List.last(dirs_to_process)
      end

    summary = %{
      dirs_scanned: dirs_count,
      files_checked: files_checked,
      orphans_deleted: orphans_deleted,
      bytes_freed: bytes_freed
    }

    {new_cursor, summary}
  end

  defp stream_leaf_dirs(root, cursor_path) do
    Stream.resource(
      fn -> [root] end,
      fn
        [] ->
          {:halt, []}

        [dir | rest] ->
          if skip_before_cursor?(dir, root, cursor_path) do
            {[], rest}
          else
            case File.ls(dir) do
              {:ok, entries} ->
                sorted = Enum.sort(entries)

                {subdirs, has_files} =
                  Enum.reduce(sorted, {[], false}, fn entry, {dirs, found_files} ->
                    full = Path.join(dir, entry)

                    case File.lstat(full) do
                      {:ok, %File.Stat{type: :directory}} -> {[full | dirs], found_files}
                      {:ok, %File.Stat{type: :regular}} -> {dirs, true}
                      _ -> {dirs, found_files}
                    end
                  end)

                sorted_subdirs = Enum.reverse(subdirs)

                if has_files do
                  {[dir], sorted_subdirs ++ rest}
                else
                  {[], sorted_subdirs ++ rest}
                end

              {:error, _} ->
                {[], rest}
            end
          end
      end,
      fn _ -> :ok end
    )
  end

  defp skip_before_cursor?(_dir, _root, nil), do: false

  defp skip_before_cursor?(dir, root, cursor_path) do
    relative = Path.relative_to(dir, root)

    relative != "." and
      relative < cursor_path and
      not String.starts_with?(cursor_path, relative <> "/")
  end

  defp keys_for_dir(dir, storage_dir, now) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.reduce(entries, {[], 0}, fn entry, {acc, count} ->
          if tmp_file?(entry) do
            {acc, count + 1}
          else
            full = Path.join(dir, entry)

            case File.lstat(full, time: :posix) do
              {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} ->
                if now - mtime >= @min_age_seconds do
                  key = Path.relative_to(full, storage_dir)
                  {[{key, size} | acc], count + 1}
                else
                  {acc, count + 1}
                end

              _ ->
                {acc, count + 1}
            end
          end
        end)

      {:error, _} ->
        {[], 0}
    end
  end

  defp delete_orphans(orphan_entries, storage_dir) do
    Enum.reduce(orphan_entries, {0, 0}, fn {key, size}, {deleted_count, freed_bytes} ->
      path = Path.join(storage_dir, key)

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

  defp tmp_file?(filename) do
    String.starts_with?(filename, [".tmp.", ".cache-upload-"])
  end

  defp log_summary(%{orphans_deleted: 0, dirs_scanned: dirs}) do
    Logger.info("Orphan scan: scanned #{dirs} directories, no orphans found")
  end

  defp log_summary(%{orphans_deleted: count, bytes_freed: bytes, dirs_scanned: dirs, files_checked: files}) do
    Logger.info(
      "Orphan scan: scanned #{dirs} directories, checked #{files} files, deleted #{count} orphans freeing #{Disk.format_bytes(bytes)}"
    )
  end
end
