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

  Safety: files younger than `@min_age_seconds` are never deleted. This
  avoids a race where an upload just completed but the ETS buffer has not
  yet flushed to SQLite. In the unlikely event that a VM crash loses an
  ETS entry for a file older than this window, the file will be correctly
  identified as an orphan and removed — the next cache miss triggers a
  re-upload, so the system is self-healing.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Cache.CacheArtifacts
  alias Cache.Config
  alias Cache.Disk
  alias Cache.OrphanScanCursors

  require Logger

  @min_age_seconds 3600

  @impl Oban.Worker
  def perform(_job) do
    storage_dir = Disk.storage_dir()
    max_dirs = Config.orphan_scan_max_dirs()
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
    now = System.os_time(:second)
    dir_results = walk_and_collect(storage_dir, cursor_path, max_dirs, now)
    dirs_count = length(dir_results)

    {all_entries, files_checked} =
      Enum.reduce(dir_results, {[], 0}, fn {_relative_dir, file_entries, checked}, {acc_entries, acc_checked} ->
        {[file_entries | acc_entries], acc_checked + checked}
      end)

    all_entries = List.flatten(all_entries)
    all_keys = Enum.map(all_entries, fn {key, _size} -> key end)
    existing_set = MapSet.new(CacheArtifacts.existing_keys(all_keys))

    orphan_entries =
      Enum.reject(all_entries, fn {key, _size} -> MapSet.member?(existing_set, key) end)

    {orphans_deleted, bytes_freed} = delete_orphans(orphan_entries, storage_dir)

    new_cursor =
      if dirs_count < max_dirs do
        nil
      else
        {last_dir, _entries, _checked} = List.last(dir_results)
        last_dir
      end

    summary = %{
      dirs_scanned: dirs_count,
      files_checked: files_checked,
      orphans_deleted: orphans_deleted,
      bytes_freed: bytes_freed
    }

    {new_cursor, summary}
  end

  # Walks the directory tree depth-first, collecting leaf directories (those
  # containing regular files) in sorted order. For each leaf, performs a
  # single lstat per entry to gather both directory structure and file
  # metadata in one pass, avoiding the double I/O of separate classify + stat.
  defp walk_and_collect(root, cursor_path, max_dirs, now) do
    do_walk([root], root, cursor_path, max_dirs, now, [])
  end

  defp do_walk([], _root, _cursor_path, _remaining, _now, acc), do: Enum.reverse(acc)
  defp do_walk(_stack, _root, _cursor_path, 0, _now, acc), do: Enum.reverse(acc)

  defp do_walk([dir | rest], root, cursor_path, remaining, now, acc) do
    relative = Path.relative_to(dir, root)

    if skip_subtree?(relative, cursor_path) do
      do_walk(rest, root, cursor_path, remaining, now, acc)
    else
      case File.ls(dir) do
        {:ok, entries} ->
          {subdirs, file_entries, files_checked} =
            classify_and_stat(entries, dir, root, now)

          has_files = files_checked > 0

          if has_files and after_cursor?(relative, cursor_path) do
            do_walk(subdirs ++ rest, root, cursor_path, remaining - 1, now, [
              {relative, file_entries, files_checked} | acc
            ])
          else
            do_walk(subdirs ++ rest, root, cursor_path, remaining, now, acc)
          end

        {:error, _} ->
          do_walk(rest, root, cursor_path, remaining, now, acc)
      end
    end
  end

  # Single-pass classification and stat: one lstat per entry, returns sorted
  # subdirectory paths, file entries eligible for orphan checking, and total
  # file count. Only subdirs are sorted (for deterministic traversal order);
  # file entries are unordered since they're consumed as a flat batch.
  defp classify_and_stat(entries, dir, root, now) do
    {subdirs, file_entries, files_checked} =
      Enum.reduce(entries, {[], [], 0}, fn entry, {dirs, files, checked} ->
        full = Path.join(dir, entry)

        case File.lstat(full, time: :posix) do
          {:ok, %File.Stat{type: :directory}} ->
            {[full | dirs], files, checked}

          {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} ->
            cond do
              tmp_file?(entry) ->
                {dirs, files, checked + 1}

              now - mtime >= @min_age_seconds ->
                key = Path.relative_to(full, root)
                {dirs, [{key, size} | files], checked + 1}

              true ->
                {dirs, files, checked + 1}
            end

          _ ->
            {dirs, files, checked}
        end
      end)

    {Enum.sort(subdirs), file_entries, files_checked}
  end

  # Returns true when `relative` is entirely before cursor_path and is NOT
  # an ancestor of it. Pruning an ancestor would skip the subtree containing
  # the cursor, which is needed to reach post-cursor directories.
  defp skip_subtree?(".", _cursor_path), do: false
  defp skip_subtree?(_relative, nil), do: false

  defp skip_subtree?(relative, cursor_path) do
    relative < cursor_path and
      not String.starts_with?(cursor_path, relative <> "/")
  end

  defp after_cursor?(_relative, nil), do: true
  defp after_cursor?(".", _cursor_path), do: false
  defp after_cursor?(relative, cursor_path), do: relative > cursor_path

  defp delete_orphans(orphan_entries, storage_dir) do
    {deleted_count, freed_bytes, parents} =
      Enum.reduce(orphan_entries, {0, 0, MapSet.new()}, fn {key, size}, {count, freed, dirs} ->
        path = Path.join(storage_dir, key)

        case File.rm(path) do
          :ok ->
            {count + 1, freed + size, MapSet.put(dirs, Path.dirname(path))}

          {:error, :enoent} ->
            {count, freed, dirs}

          {:error, reason} ->
            Logger.warning("Failed to delete orphan #{key}: #{inspect(reason)}")
            {count, freed, dirs}
        end
      end)

    cleanup_empty_dirs(parents, storage_dir)

    {deleted_count, freed_bytes}
  end

  # Attempts to remove directories left empty after orphan deletion.
  # Walks up the tree from each leaf, stopping at storage_dir or when
  # a directory is non-empty (File.rmdir fails on non-empty dirs).
  defp cleanup_empty_dirs(dirs, storage_dir) do
    dirs
    |> Enum.sort(:desc)
    |> Enum.each(&try_remove_empty_ancestors(&1, storage_dir))
  end

  defp try_remove_empty_ancestors(dir, storage_dir) when dir == storage_dir, do: :ok

  defp try_remove_empty_ancestors(dir, storage_dir) do
    case File.rmdir(dir) do
      :ok -> try_remove_empty_ancestors(Path.dirname(dir), storage_dir)
      {:error, _} -> :ok
    end
  end

  defp tmp_file?(filename) do
    String.starts_with?(filename, [".tmp.", ".cache-upload-"])
  end

  defp log_summary(%{orphans_deleted: 0, dirs_scanned: dirs}) do
    Logger.info("Orphan scan: scanned #{dirs} directories, no orphans found")
  end

  defp log_summary(%{orphans_deleted: count, bytes_freed: bytes, dirs_scanned: dirs, files_checked: files}) do
    Logger.info(
      "Orphan scan: scanned #{dirs} directories, checked #{files} files, " <>
        "deleted #{count} orphans freeing #{Disk.format_bytes(bytes)}"
    )
  end
end
