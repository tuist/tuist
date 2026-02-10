defmodule Cache.Gradle.Disk do
  @moduledoc """
  Local disk storage backend for Gradle build cache artifacts.

  Stores Gradle artifacts on the local filesystem with two-level directory sharding
  to prevent ext4 directory index overflow.
  """

  alias Cache.Disk

  require Logger

  @doc """
  Constructs a sharded Gradle build cache key from account handle, project handle, and cache key hash.

  Uses a two-level directory sharding based on the first 4 characters of the cache key
  to prevent directory index overflow on ext4 filesystems without `large_dir` enabled.

  ## Examples

      iex> Cache.Gradle.Disk.key("account", "project", "ABCD1234")
      "account/project/gradle/AB/CD/ABCD1234"
  """
  @spec key(binary(), binary(), binary()) :: binary()
  def key(account_handle, project_handle, cache_key) do
    {shard1, shard2} = Disk.shards_for_id(cache_key)
    "#{account_handle}/#{project_handle}/gradle/#{shard1}/#{shard2}/#{cache_key}"
  end

  @doc """
  Checks if a Gradle build cache artifact exists on disk.

  ## Examples

      iex> Cache.Gradle.Disk.exists?("account", "project", "abc123")
      true
  """
  @spec exists?(binary(), binary(), binary()) :: boolean()
  def exists?(account_handle, project_handle, cache_key) do
    account_handle
    |> key(project_handle, cache_key)
    |> Disk.artifact_path()
    |> File.exists?()
  end

  @doc """
  Writes Gradle build cache artifact data to disk for given account, project, and cache key.

  Accepts either binary data or a file path. For file paths, file is moved
  into place without reading into memory (efficient for large uploads).

  Creates parent directories if they don't exist.

  ## Examples

      iex> Cache.Gradle.Disk.put("account", "project", "abc123", <<1, 2, 3>>)
      :ok

      iex> Cache.Gradle.Disk.put("account", "project", "abc123", {:file, "/tmp/upload-123"})
      :ok
  """
  @spec put(binary(), binary(), binary(), binary() | {:file, binary()}) :: :ok | {:error, atom()}
  def put(account_handle, project_handle, cache_key, {:file, tmp_path}) do
    path = account_handle |> key(project_handle, cache_key) |> Disk.artifact_path()

    with :ok <- Disk.ensure_directory(path) do
      Disk.move_file(tmp_path, path)
    end
  end

  def put(account_handle, project_handle, cache_key, data) when is_binary(data) do
    path = account_handle |> key(project_handle, cache_key) |> Disk.artifact_path()

    with :ok <- Disk.ensure_directory(path),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to write Gradle artifact to #{path}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Returns file stat information for a Gradle build cache artifact.

  ## Examples

      iex> Cache.Gradle.Disk.stat("account", "project", "ABCD1234")
      {:ok, %File.Stat{size: 1024, ...}}
  """
  @spec stat(binary(), binary(), binary()) :: {:ok, File.Stat.t()} | {:error, atom()}
  def stat(account_handle, project_handle, cache_key) do
    account_handle
    |> key(project_handle, cache_key)
    |> Disk.artifact_path()
    |> File.stat()
  end

  @doc """
  Build the internal X-Accel-Redirect path for a Gradle build cache artifact.

  The returned path maps to the nginx internal location that aliases the
  physical storage directory.
  """
  @spec local_accel_path(binary(), binary(), binary()) :: binary()
  def local_accel_path(account_handle, project_handle, cache_key) do
    "/internal/local/" <> key(account_handle, project_handle, cache_key)
  end
end
