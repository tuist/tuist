defmodule Cache.Disk do
  @moduledoc """
  Shared disk infrastructure for cache artifact storage.

  Provides common disk operations used by all cache domains (Xcode, Gradle, Registry, Module).
  Handles artifact path construction, directory sharding, file operations, and disk usage monitoring.

  Domain-specific disk operations are implemented in:
  - `Cache.Xcode.Disk` - Xcode compilation cache operations
  - `Cache.Gradle.Disk` - Gradle build cache operations
  - `Cache.Registry.Disk` - Swift package registry operations
  - `Cache.XcodeModule.Disk` - Xcode module cache operations

  This module stores artifacts on the local filesystem with configurable storage directory.
  Uses two-level directory sharding to prevent ext4 directory index overflow.
  """

  require Logger

  @cleanup_progress_chunk_size 1_000

  @doc """
  Converts a cache key to an absolute file system path.

  ## Examples

      iex> Cache.Disk.artifact_path("account/project/xcode/AB/CD/ABCD1234")
      "/var/tuist/cas/account/project/xcode/AB/CD/ABCD1234"
  """
  def artifact_path(key) do
    Path.join(storage_dir(), key)
  end

  @doc """
  Extracts two-character shards from a hex ID for directory sharding.

  Takes the first 4 characters of a hex ID and splits them into two 2-character shards
  to prevent ext4 directory index overflow on filesystems without `large_dir` enabled.

  ## Examples

      iex> Cache.Disk.shards_for_id("ABCD1234")
      {"AB", "CD"}
  """
  def shards_for_id(<<shard1::binary-size(2), shard2::binary-size(2), _rest::binary>>) do
    {shard1, shard2}
  end

  @doc """
  Returns the configured storage directory for cache artifacts.

  Defaults to "tmp/cas" if not configured.
  """
  def storage_dir do
    Application.get_env(:cache, :storage_dir)
  end

  @doc """
  Returns the base path prefix used for nginx internal X-Accel-Redirect responses.

  All domain-specific `local_accel_path` functions prepend this to their cache key
  so the literal lives in one place.

  ## Examples

      iex> Cache.Disk.local_base_path()
      "/internal/local/"
  """
  def local_base_path, do: "/internal/local/"

  @doc """
  Lists all artifact paths on disk.
  """
  def list_artifact_paths(dir \\ storage_dir()) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
  end

  @doc """
  Deletes a single artifact from disk by its cache key.

  Returns `:ok` on success, `{:error, :enoent}` if the file doesn't exist,
  or `{:error, reason}` on other failures.
  """
  def delete_artifact(key) do
    key |> artifact_path() |> File.rm()
  end

  @doc """
  Deletes all artifacts for a project from disk.

  Removes the entire project directory, which includes both Xcode cache and module cache artifacts.
  Returns :ok on success, {:error, reason} on failure.
  """
  def delete_project(account_handle, project_handle) do
    case File.rm_rf(project_path(account_handle, project_handle)) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Deletes project artifacts only when their current mtime is strictly before the
  cutoff second.
  """
  def delete_project_files_before(account_handle, project_handle, cutoff, opts \\ []) do
    path = project_path(account_handle, project_handle)
    on_progress = Keyword.get(opts, :on_progress)
    on_deleted_keys = Keyword.get(opts, :on_deleted_keys)

    if File.exists?(path) do
      path
      |> stream_regular_files()
      |> delete_files_before(DateTime.truncate(cutoff, :second), on_progress, on_deleted_keys)
    else
      {:ok, 0}
    end
  end

  @doc """
  Returns disk usage stats for the filesystem that backs the provided path.
  """
  def usage(path) when is_binary(path) do
    expanded_path = Path.expand(path)

    case System.cmd("df", ["-Pk", expanded_path], stderr_to_stdout: true) do
      {output, 0} ->
        parse_df_output(output)

      {output, exit_code} ->
        Logger.warning("df exited with #{exit_code} while inspecting #{expanded_path}: #{String.trim(output)}")

        {:error, :df_failed}
    end
  end

  @doc """
  Creates a directory and all parent directories if they don't exist.

  Uses `File.mkdir_p/1` to create the directory structure and logs any errors
  that occur during creation.

  ## Examples

      iex> Cache.Disk.ensure_directory("/path/to/file.txt")
      :ok
  """
  def ensure_directory(file_path) do
    dir = Path.dirname(file_path)

    case File.mkdir_p(dir) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to create directory #{dir}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Atomically moves a file from a temporary path to a target path.

  Checks that the target path doesn't already exist before performing the rename.
  Returns `{:error, :exists}` if the target file already exists, or logs and returns
  the error reason if the rename operation fails.

  ## Examples

      iex> Cache.Disk.move_file("/tmp/upload-123", "/storage/artifact")
      :ok
  """
  def move_file(tmp_path, target_path) do
    with false <- File.exists?(target_path),
         :ok <- File.rename(tmp_path, target_path) do
      :ok
    else
      true ->
        {:error, :exists}

      {:error, reason} ->
        Logger.error("Failed to move artifact to #{target_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_df_output(output) do
    lines =
      output
      |> String.trim()
      |> String.split("\n", trim: true)

    case lines do
      [_header, data_line | _] ->
        parse_df_data_line(data_line)

      _ ->
        {:error, :unexpected_df_output}
    end
  end

  defp parse_df_data_line(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [_filesystem, blocks, used, available, capacity | _] ->
        with {:ok, total_bytes} <- parse_kbytes(blocks),
             {:ok, used_bytes} <- parse_kbytes(used),
             {:ok, available_bytes} <- parse_kbytes(available),
             {:ok, percent_used} <- parse_percent(capacity) do
          {:ok,
           %{
             total_bytes: total_bytes,
             used_bytes: used_bytes,
             available_bytes: available_bytes,
             percent_used: percent_used
           }}
        end

      _ ->
        {:error, :unexpected_df_fields}
    end
  end

  defp parse_kbytes(value) do
    case Integer.parse(value) do
      {int, _} when int >= 0 -> {:ok, int * 1024}
      _ -> {:error, :invalid_number}
    end
  end

  defp parse_percent(value) do
    sanitized = String.trim_trailing(value, "%")

    case Float.parse(sanitized) do
      {number, _} when number >= 0 -> {:ok, number}
      _ -> {:error, :invalid_percent}
    end
  end

  @doc """
  Formats a byte count as a human-readable string.

  ## Examples

      iex> Cache.Disk.format_bytes(512)
      "512 B"

      iex> Cache.Disk.format_bytes(1_536)
      "1.5 KB"
  """
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 2)} KB"
  def format_bytes(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 2)} MB"
  def format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  defp stat_mtime_to_datetime({{year, month, day}, {hour, minute, second}}) do
    year
    |> NaiveDateTime.new(month, day, hour, minute, second)
    |> case do
      {:ok, naive} -> DateTime.from_naive(naive, "Etc/UTC")
      error -> error
    end
  end

  defp delete_files_before(files_stream, safe_cutoff, on_progress, on_deleted_keys) do
    files_stream
    |> Stream.chunk_every(@cleanup_progress_chunk_size)
    |> Enum.reduce_while({:ok, 0}, fn files_chunk, {:ok, deleted_acc} ->
      with :ok <- maybe_call_progress(on_progress),
           {:ok, chunk_deleted_count, chunk_deleted_keys} <- delete_files_chunk_before(files_chunk, safe_cutoff),
           :ok <- maybe_call_on_deleted_keys(on_deleted_keys, chunk_deleted_keys) do
        {:cont, {:ok, deleted_acc + chunk_deleted_count}}
      else
        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_call_progress(nil), do: :ok
  defp maybe_call_progress(fun) when is_function(fun, 0), do: fun.()

  defp maybe_call_on_deleted_keys(_fun, []), do: :ok
  defp maybe_call_on_deleted_keys(nil, _keys), do: :ok
  defp maybe_call_on_deleted_keys(fun, keys) when is_function(fun, 1), do: fun.(keys)

  defp delete_files_chunk_before(files, safe_cutoff) do
    Enum.reduce_while(files, {:ok, 0, []}, fn
      {:error, reason}, {:ok, _deleted_acc, _keys_acc} ->
        {:halt, {:error, reason}}

      file_path, {:ok, deleted_acc, keys_acc} when is_binary(file_path) ->
        case delete_file_if_before(file_path, safe_cutoff) do
          :deleted ->
            key = path_to_key(file_path)
            {:cont, {:ok, deleted_acc + 1, [key | keys_acc]}}

          :skipped ->
            {:cont, {:ok, deleted_acc, keys_acc}}

          {:error, :enoent} ->
            {:cont, {:ok, deleted_acc, keys_acc}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
    end)
  end

  defp delete_file_if_before(file_path, safe_cutoff) do
    with {:ok, %File.Stat{mtime: mtime}} <- File.stat(file_path, time: :universal),
         {:ok, mtime_datetime} <- stat_mtime_to_datetime(mtime),
         true <- DateTime.before?(mtime_datetime, safe_cutoff),
         :ok <- File.rm(file_path) do
      :deleted
    else
      false -> :skipped
      {:error, reason} -> {:error, reason}
    end
  end

  defp stream_regular_files(root) do
    Stream.resource(
      fn -> [root] end,
      fn
        [] ->
          {:halt, []}

        [dir | rest] ->
          case File.ls(dir) do
            {:ok, entries} ->
              case entries |> Enum.map(&Path.join(dir, &1)) |> classify_paths() do
                {:ok, {regular, subdirs}} ->
                  {regular, subdirs ++ rest}

                {:error, reason} ->
                  {[{:error, reason}], []}
              end

            {:error, reason} ->
              {[{:error, {:ls_failed, dir, reason}}], []}
          end
      end,
      fn _ -> :ok end
    )
  end

  defp classify_paths(paths) do
    Enum.reduce_while(paths, {:ok, {[], []}}, fn path, {:ok, {regular_acc, dir_acc}} ->
      case File.lstat(path) do
        {:ok, %File.Stat{type: :regular}} ->
          {:cont, {:ok, {[path | regular_acc], dir_acc}}}

        {:ok, %File.Stat{type: :directory}} ->
          {:cont, {:ok, {regular_acc, [path | dir_acc]}}}

        {:ok, %File.Stat{type: :symlink}} ->
          {:cont, {:ok, {regular_acc, dir_acc}}}

        {:ok, _stat} ->
          {:cont, {:ok, {regular_acc, dir_acc}}}

        {:error, reason} ->
          {:halt, {:error, {:lstat_failed, path, reason}}}
      end
    end)
  end

  defp project_path(account_handle, project_handle) do
    Path.join(storage_dir(), "#{account_handle}/#{project_handle}")
  end

  defp path_to_key(file_path) do
    Path.relative_to(file_path, storage_dir())
  end
end
