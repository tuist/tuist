defmodule Cache.Disk do
  @moduledoc """
  Local disk storage backend for CAS (Content Addressable Storage).

  Stores artifacts on the local filesystem with configurable storage directory.
  """

  require Logger

  @doc """
  Checks if an artifact exists on disk.

  ## Examples

      iex> Cache.Disk.exists?("account", "project", "abc123")
      true
  """

  def exists?(account_handle, project_handle, id) do
    account_handle
    |> cas_key(project_handle, id)
    |> artifact_path()
    |> File.exists?()
  end

  @doc """
  Writes data to disk for given account, project, and artifact ID.

  Accepts either binary data or a file path. For file paths, file is moved
  into place without reading into memory (efficient for large uploads).

  Creates parent directories if they don't exist.

  ## Examples

      iex> Cache.Disk.put("account", "project", "abc123", <<1, 2, 3>>)
      :ok

      iex> Cache.Disk.put("account", "project", "abc123", {:file, "/tmp/upload-123"})
      :ok
  """

  def put(account_handle, project_handle, id, {:file, tmp_path}) do
    path = account_handle |> cas_key(project_handle, id) |> artifact_path()

    with :ok <- ensure_directory(path),
         :ok <- move_file(tmp_path, path) do
      :ok
    else
      {:error, _} = error ->
        File.rm(tmp_path)
        error
    end
  end

  def put(account_handle, project_handle, id, data) when is_binary(data) do
    path = account_handle |> cas_key(project_handle, id) |> artifact_path()

    with :ok <- ensure_directory(path),
         :ok <- File.write(path, data) do
      :ok
    else
      {:error, reason} = error ->
        Logger.error("Failed to write CAS artifact to #{path}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Converts a CAS key to an absolute file system path.

  ## Examples

      iex> Cache.Disk.artifact_path("account/project/cas/abc123")
      "/var/tuist/cas/account/project/cas/abc123"
  """

  def artifact_path(key) do
    Path.join(storage_dir(), key)
  end

  @doc """
  Constructs a CAS key from account handle, project handle, and artifact ID.

  ## Examples

      iex> Cache.Disk.cas_key("account", "project", "abc123")
      "account/project/cas/abc123"
  """
  def cas_key(account_handle, project_handle, id) do
    "#{account_handle}/#{project_handle}/cas/#{id}"
  end

  @doc """
  Returns the configured storage directory for CAS artifacts.

  Defaults to "tmp/cas" if not configured.
  """

  def storage_dir do
    Application.get_env(:cache, :cas)[:storage_dir]
  end

  @doc """
  Returns local file path for a given account, project, and artifact ID if the file exists.

  ## Examples

      iex> Cache.Disk.get_local_path("account", "project", "abc123")
      {:ok, "/var/tuist/cas/account/project/cas/abc123"}
  """
  def get_local_path(account_handle, project_handle, id) do
    path = account_handle |> cas_key(project_handle, id) |> artifact_path()

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, :not_found}
    end
  end

  defp ensure_directory(file_path) do
    dir = Path.dirname(file_path)

    case File.mkdir_p(dir) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to create directory #{dir}: #{inspect(reason)}")
        error
    end
  end

  defp move_file(tmp_path, target_path) do
    with false <- File.exists?(target_path),
         :ok <- File.rename(tmp_path, target_path) do
      :ok
    else
      true ->
        File.rm(tmp_path)
        {:error, :exists}

      {:error, reason} ->
        File.rm(tmp_path)
        Logger.error("Failed to move CAS artifact to #{target_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
