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
    path = Path.join(storage_dir(), "#{account_handle}/#{project_handle}")

    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
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
  Publishes a temporary file at a target path, unless an artifact is already there.

  The file is hard-linked into place, which fails atomically when the target
  exists, where a rename would silently replace it. Of several uploads racing
  for one key exactly one publishes, so the bytes on disk and the digest
  recorded for them come from the same upload. The temporary file is removed
  once published; on `{:error, :exists}` it is left for the caller to clean up.
  Other failures are logged and returned. Both paths must be on the same
  filesystem.

  ## Examples

      iex> Cache.Disk.move_file("/tmp/upload-123", "/storage/artifact")
      :ok
  """
  def move_file(tmp_path, target_path) do
    case File.ln(tmp_path, target_path) do
      :ok ->
        with {:error, reason} <- File.rm(tmp_path) do
          Logger.warning("Published #{target_path} but could not remove #{tmp_path}: #{inspect(reason)}")
        end

        :ok

      {:error, :eexist} ->
        {:error, :exists}

      {:error, reason} ->
        Logger.error("Failed to move artifact to #{target_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Publishes `data` at `target_path` through a temporary file next to it, with
  the same refusal of an existing artifact as `move_file/2`. A direct write
  would let two uploads interleave into one file and expose a partial one to
  readers.
  """
  def write_new_file(target_path, data) do
    tmp_path =
      Path.join(Path.dirname(target_path), ".tmp.#{Path.basename(target_path)}.#{System.unique_integer([:positive])}")

    result =
      case File.write(tmp_path, data) do
        :ok ->
          move_file(tmp_path, target_path)

        {:error, reason} = error ->
          Logger.error("Failed to write artifact to #{tmp_path}: #{inspect(reason)}")
          error
      end

    if result != :ok, do: File.rm(tmp_path)
    result
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
end
