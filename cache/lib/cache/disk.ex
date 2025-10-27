defmodule Cache.Disk do
  @moduledoc """
  Local disk storage backend for CAS (Content Addressable Storage).

  Stores artifacts on the local filesystem with configurable storage directory.
  """

  require Logger

  @doc """
  Checks if an artifact exists on disk.

  ## Examples

      iex> Cache.Disk.exists?("account/project/cas/abc123")
      true
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(key) do
    key
    |> artifact_path()
    |> File.exists?()
  end

  @doc """
  Returns a stream for reading an artifact from disk.

  Streams the file in chunks for memory efficiency with large files.

  ## Examples

      iex> Cache.Disk.stream("account/project/cas/abc123")
      #Stream<...>
  """
  @spec stream(String.t()) :: Enumerable.t()
  def stream(key) do
    key
    |> artifact_path()
    |> File.stream!([], 64_000)
  end

  @doc """
  Writes data to disk for the given key.

  Creates parent directories if they don't exist.

  ## Examples

      iex> Cache.Disk.put("account/project/cas/abc123", <<1, 2, 3>>)
      :ok
  """
  @spec put(String.t(), binary()) :: :ok | {:error, term()}
  def put(key, data) do
    path = artifact_path(key)

    case ensure_directory(path) do
      :ok ->
        case File.write(path, data) do
          :ok ->
            :ok

          {:error, reason} = error ->
            Logger.error("Failed to write CAS artifact to #{path}: #{inspect(reason)}")
            error
        end

      error ->
        error
    end
  end

  @doc """
  Moves a temporary file into place for the given key without reading it into memory.
  """
  @spec put_file(String.t(), Path.t()) :: :ok | {:error, term()}
  def put_file(key, tmp_path) do
    path = artifact_path(key)

    case ensure_directory(path) do
      :ok ->
        do_move_file(tmp_path, path)

      {:error, _} = error ->
        File.rm(tmp_path)
        error
    end
  end

  @doc """
  Converts a CAS key to an absolute file system path.

  ## Examples

      iex> Cache.Disk.artifact_path("account/project/cas/abc123")
      "/var/tuist/cas/account/project/cas/abc123"
  """
  @spec artifact_path(String.t()) :: Path.t()
  def artifact_path(key) do
    Path.join(storage_dir(), key)
  end

  @doc """
  Returns the configured storage directory for CAS artifacts.

  Defaults to "tmp/cas" if not configured.
  """
  @spec storage_dir() :: Path.t()
  def storage_dir do
    Application.get_env(:cache, :cas)[:storage_dir] || "tmp/cas"
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

  defp do_move_file(tmp_path, target_path) do
    if File.exists?(target_path) do
      File.rm(tmp_path)
      {:error, :exists}
    else
      case File.rename(tmp_path, target_path) do
        :ok ->
          :ok

        {:error, :exdev} ->
          case File.cp(tmp_path, target_path) do
            :ok ->
              File.rm(tmp_path)
              :ok

            {:error, reason} = error ->
              File.rm(tmp_path)
              Logger.error("Failed to copy CAS artifact to #{target_path}: #{inspect(reason)}")
              error
          end

        {:error, reason} = error ->
          File.rm(tmp_path)
          Logger.error("Failed to move CAS artifact to #{target_path}: #{inspect(reason)}")
          error
      end
    end
  end
end
