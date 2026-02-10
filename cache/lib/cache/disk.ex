defmodule Cache.Disk do
  @moduledoc """
  Local disk storage backend for Xcode compilation cache (CAS) and module cache artifacts.

  Stores artifacts on the local filesystem with configurable storage directory.
  Uses two-level directory sharding to prevent ext4 directory index overflow.
  """

  require Logger

  @doc """
  Converts a cache key to an absolute file system path.

  ## Examples

      iex> Cache.Disk.artifact_path("account/project/cas/AB/CD/ABCD1234")
      "/var/tuist/cas/account/project/cas/AB/CD/ABCD1234"
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
  @spec shards_for_id(binary()) :: {binary(), binary()}
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
  Lists all artifact paths on disk.
  """
  def list_artifact_paths(dir \\ storage_dir()) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
  end

  @doc """
  Deletes all artifacts for a project from disk.

  Removes the entire project directory, which includes both CAS and module cache artifacts.
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
  @spec ensure_directory(binary()) :: :ok | {:error, atom()}
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
  @spec move_file(binary(), binary()) :: :ok | {:error, atom()}
  def move_file(tmp_path, target_path) do
    with false <- File.exists?(target_path),
         :ok <- File.rename(tmp_path, target_path) do
      :ok
    else
      true ->
        {:error, :exists}

      {:error, reason} ->
        Logger.error("Failed to move CAS artifact to #{target_path}: #{inspect(reason)}")
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
end
