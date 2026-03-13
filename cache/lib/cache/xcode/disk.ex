defmodule Cache.Xcode.Disk do
  @moduledoc """
  Local disk storage backend for Xcode compilation cache artifacts.

  Stores Xcode cache artifacts on the local filesystem with two-level directory sharding
  to prevent ext4 directory index overflow.
  """

  alias Cache.Disk

  require Logger

  @doc """
  Constructs a sharded Xcode compilation cache key from account handle, project handle, and artifact ID.

  Uses a two-level directory sharding based on the first 4 characters of the artifact ID
  to prevent directory index overflow on ext4 filesystems without `large_dir` enabled.

  ## Examples

      iex> Cache.Xcode.Disk.key("account", "project", "ABCD1234")
      "account/project/xcode/AB/CD/ABCD1234"
  """
  def key(account_handle, project_handle, id) do
    {shard1, shard2} = Disk.shards_for_id(id)
    "#{account_handle}/#{project_handle}/xcode/#{shard1}/#{shard2}/#{id}"
  end

  @doc """
  Checks if a Xcode compilation cache artifact exists on disk.

  ## Examples

      iex> Cache.Xcode.Disk.exists?("account", "project", "abc123")
      true
  """
  def exists?(account_handle, project_handle, id) do
    account_handle
    |> key(project_handle, id)
    |> Disk.artifact_path()
    |> File.exists?()
  end

  @doc """
  Writes Xcode compilation cache artifact data to disk for given account, project, and artifact ID.

  Accepts either binary data or a file path. For file paths, file is moved
  into place without reading into memory (efficient for large uploads).

  Creates parent directories if they don't exist.

  ## Examples

     iex> Cache.Xcode.Disk.put("account", "project", "abc123", <<1, 2, 3>>)
     :ok

      iex> Cache.Xcode.Disk.put("account", "project", "abc123", {:file, "/tmp/upload-123"})
      :ok
  """
  def put(account_handle, project_handle, id, {:file, tmp_path}) do
    path = account_handle |> key(project_handle, id) |> Disk.artifact_path()

    with :ok <- Disk.ensure_directory(path) do
      Disk.move_file(tmp_path, path)
    end
  end

  def put(account_handle, project_handle, id, data) when is_binary(data) do
    path = account_handle |> key(project_handle, id) |> Disk.artifact_path()

    with :ok <- Disk.ensure_directory(path),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to write Xcode cache artifact to #{path}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Ensures the parent directory for a Xcode cache artifact exists and returns its path.

  Returns `{:ok, dir_path}` on success, or `{:error, reason}` if directory creation fails.
  """
  def ensure_artifact_directory(account_handle, project_handle, id) do
    path = account_handle |> key(project_handle, id) |> Disk.artifact_path()
    dir = Path.dirname(path)

    with :ok <- Disk.ensure_directory(path) do
      {:ok, dir}
    end
  end

  @doc """
  Returns file stat information for a Xcode compilation cache artifact.

  ## Examples

      iex> Cache.Xcode.Disk.stat("account", "project", "ABCD1234")
      {:ok, %File.Stat{size: 1024, ...}}
  """
  def stat(account_handle, project_handle, id) do
    account_handle
    |> key(project_handle, id)
    |> Disk.artifact_path()
    |> File.stat()
  end

  @doc """
  Build the internal X-Accel-Redirect path for a Xcode compilation cache artifact.

  The returned path maps to the nginx internal location that aliases the
  physical Xcode cache storage directory.
  """
  def local_accel_path(account_handle, project_handle, id) do
    Disk.local_base_path() <> key(account_handle, project_handle, id)
  end

  @doc """
  Returns local file path for a given Xcode compilation cache artifact if the file exists.

  ## Examples

      iex> Cache.Xcode.Disk.get_local_path("account", "project", "ABCD1234")
      {:ok, "/var/tuist/cas/account/project/xcode/AB/CD/ABCD1234"}
  """
  def get_local_path(account_handle, project_handle, id) do
    path = account_handle |> key(project_handle, id) |> Disk.artifact_path()

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, :not_found}
    end
  end
end
