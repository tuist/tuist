defmodule Cache.Module.Disk do
  @moduledoc """
  Local disk storage backend for Module cache artifacts.

  Stores Module cache artifacts on the local filesystem with two-level directory sharding
  to prevent ext4 directory index overflow.
  """

  alias Cache.Disk

  require Logger

  @doc """
  Constructs a sharded module cache key from account handle, project handle, category, hash, and name.

  Uses a two-level directory sharding based on the first 4 characters of the hash
  to prevent directory index overflow on ext4 filesystems without `large_dir` enabled.

  ## Examples

      iex> Cache.Module.Disk.key("account", "project", "builds", "ABCD1234", "MyModule.xcframework.zip")
      "account/project/module/builds/AB/CD/ABCD1234/MyModule.xcframework.zip"
  """
  @spec key(binary(), binary(), binary(), binary(), binary()) :: binary()
  def key(account_handle, project_handle, category, hash, name) do
    {shard1, shard2} = Disk.shards_for_id(hash)
    "#{account_handle}/#{project_handle}/module/#{category}/#{shard1}/#{shard2}/#{hash}/#{name}"
  end

  @doc """
  Checks if a module artifact exists on disk.

  ## Examples

      iex> Cache.Module.Disk.exists?("account", "project", "builds", "abc123", "MyModule.xcframework.zip")
      true
  """
  @spec exists?(binary(), binary(), binary(), binary(), binary()) :: boolean()
  def exists?(account_handle, project_handle, category, hash, name) do
    account_handle
    |> key(project_handle, category, hash, name)
    |> Disk.artifact_path()
    |> File.exists?()
  end

  @doc """
  Writes module artifact data to disk.

  Accepts either binary data or a file path tuple.
  """
  @spec put(binary(), binary(), binary(), binary(), binary(), binary() | {:file, binary()}) ::
          :ok | {:error, atom()}
  def put(account_handle, project_handle, category, hash, name, {:file, tmp_path}) do
    path = account_handle |> key(project_handle, category, hash, name) |> Disk.artifact_path()

    with :ok <- Disk.ensure_directory(path) do
      Disk.move_file(tmp_path, path)
    end
  end

  def put(account_handle, project_handle, category, hash, name, data) when is_binary(data) do
    path = account_handle |> key(project_handle, category, hash, name) |> Disk.artifact_path()

    with :ok <- Disk.ensure_directory(path),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to write module artifact to #{path}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Assembles multiple part files into a single module artifact.

  Creates the artifact from ordered part files using efficient file copying.
  Returns {:error, :exists} if the artifact already exists.
  """
  @spec put_from_parts(binary(), binary(), binary(), binary(), binary(), [binary()]) ::
          :ok | {:error, atom()}
  def put_from_parts(account_handle, project_handle, category, hash, name, part_paths) do
    dest_path =
      account_handle |> key(project_handle, category, hash, name) |> Disk.artifact_path()

    with :ok <- Disk.ensure_directory(dest_path),
         false <- File.exists?(dest_path) do
      tmp_dest = dest_path <> ".tmp.#{:erlang.unique_integer([:positive])}"

      with {:ok, :ok} <-
             File.open(tmp_dest, [:write, :append, :binary], &copy_parts_to_file(part_paths, &1)),
           :ok <- File.rename(tmp_dest, dest_path) do
        :ok
      else
        {:ok, {:error, reason}} ->
          Logger.error("Failed to assemble artifact to #{dest_path}: #{inspect(reason)}")
          File.rm(tmp_dest)
          {:error, reason}

        {:error, :eexist} ->
          File.rm(tmp_dest)
          {:error, :exists}

        {:error, reason} ->
          Logger.error("Failed to assemble artifact to #{dest_path}: #{inspect(reason)}")
          File.rm(tmp_dest)
          {:error, reason}
      end
    else
      true -> {:error, :exists}
      {:error, reason} -> {:error, reason}
    end
  end

  defp copy_parts_to_file(part_paths, dest_file) do
    Enum.reduce_while(part_paths, :ok, fn part_path, :ok ->
      case File.open(part_path, [:read, :binary, :raw]) do
        {:ok, source} ->
          result = :file.copy(source, dest_file)
          File.close(source)

          case result do
            {:ok, _bytes_copied} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Returns file stat information for a module artifact.

  ## Examples

      iex> Cache.Module.Disk.stat("account", "project", "builds", "ABCD1234", "MyModule.xcframework.zip")
      {:ok, %File.Stat{size: 1024, ...}}
  """
  @spec stat(binary(), binary(), binary(), binary(), binary()) ::
          {:ok, File.Stat.t()} | {:error, atom()}
  def stat(account_handle, project_handle, category, hash, name) do
    account_handle
    |> key(project_handle, category, hash, name)
    |> Disk.artifact_path()
    |> File.stat()
  end

  @doc """
  Build the internal X-Accel-Redirect path for a module artifact.

  The returned path maps to the nginx internal location that aliases the
  physical module storage directory.
  """
  @spec local_accel_path(binary(), binary(), binary(), binary(), binary()) :: binary()
  def local_accel_path(account_handle, project_handle, category, hash, name) do
    "/internal/local/" <> key(account_handle, project_handle, category, hash, name)
  end
end
