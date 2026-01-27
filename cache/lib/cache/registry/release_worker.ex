defmodule Cache.Registry.ReleaseWorker do
  @moduledoc """
  Downloads and uploads missing registry artifacts, and updates metadata in S3.
  """

  use Oban.Worker, queue: :registry_sync

  alias Cache.Registry.GitHub
  alias Cache.Registry.KeyNormalizer
  alias Cache.Registry.Lock
  alias Cache.Registry.Metadata

  require Logger

  @alternate_manifest_regex ~r/\APackage@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?\.swift\z/
  @lock_ttl_seconds 1_800
  @metadata_lock_ttl_seconds 300

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"scope" => scope, "name" => name, "repository_full_handle" => full_handle, "tag" => tag}}) do
    lock_key = {:release, scope, name, KeyNormalizer.normalize_version(tag)}

    case Lock.try_acquire(lock_key, @lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          do_sync_release(scope, name, full_handle, tag)
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        :ok
    end
  end

  defp do_sync_release(scope, name, full_handle, tag) do
    token = registry_token()

    if is_nil(token) or token == "" do
      Logger.warning("Registry release sync skipped for #{scope}/#{name}@#{tag}: missing token")
      :ok
    else
      normalized_version = KeyNormalizer.normalize_version(tag)

      case Metadata.get_package(scope, name, fresh: true) do
        {:ok, metadata} ->
          releases = Map.get(metadata, "releases", %{})

          if Map.has_key?(releases, normalized_version) do
            :ok
          else
            sync_release(scope, name, full_handle, tag, normalized_version, token)
          end

        {:error, :not_found} ->
          sync_release(scope, name, full_handle, tag, normalized_version, token)
      end
    end
  end

  defp sync_release(scope, name, full_handle, tag, version, token) do
    tmp_dir = temp_dir()
    archive_path = Path.join(tmp_dir, "source_archive.zip")

    try do
      with :ok <- fetch_source_archive(full_handle, tag, token, tmp_dir, archive_path),
           {:ok, checksum} <- checksum_for_file(archive_path),
           :ok <- upload_source_archive(scope, name, version, archive_path),
           {:ok, manifests} <- fetch_and_upload_manifests(scope, name, version, full_handle, tag, token) do
        update_metadata_with_release(scope, name, full_handle, version, checksum, manifests)
      else
        {:error, reason} ->
          Logger.warning("Failed to sync release #{scope}/#{name}@#{tag}: #{inspect(reason)}")
          {:error, reason}
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp fetch_source_archive(full_handle, tag, token, tmp_dir, archive_path) do
    if has_submodules?(full_handle, tag, token) do
      with {:ok, source_directory} <- clone_with_submodules(full_handle, tag, token, tmp_dir) do
        zip_directory(source_directory, archive_path)
      end
    else
      GitHub.download_zipball(full_handle, token, tag, archive_path)
    end
  end

  defp has_submodules?(full_handle, tag, token) do
    case GitHub.get_file_content(full_handle, token, ".gitmodules", tag) do
      {:ok, content} -> content != ""
      {:error, :not_found} -> false
      {:error, _reason} -> false
    end
  end


  defp clone_with_submodules(full_handle, tag, token, tmp_dir) do
    repo_name = full_handle |> String.split("/") |> List.last()
    clone_dest = Path.join(tmp_dir, "#{repo_name}-#{String.replace(tag, "/", "-")}")
    clone_url = "https://#{token}@github.com/#{full_handle}.git"

    case System.cmd(
           "git",
           [
             "-c",
             "url.https://github.com/.insteadOf=git@github.com:",
             "clone",
             "--depth",
             "1",
             "--branch",
             tag,
             clone_url,
             clone_dest
           ],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        case update_submodules(%{destination: clone_dest, repository_full_handle: full_handle, tag: tag}) do
          :ok ->
            remove_git_metadata(clone_dest)
            {:ok, clone_dest}

          {:error, reason} ->
            {:error, reason}
        end

      {_output, status} ->
        {:error, {:git_clone_failed, status}}
    end
  end

  defp update_submodules(%{destination: destination, repository_full_handle: full_handle, tag: tag}) do
    destination
    |> submodule_paths()
    |> Enum.reduce_while(:ok, fn submodule_path, :ok ->
      case System.cmd(
             "git",
             [
               "-c",
               "url.https://github.com/.insteadOf=git@github.com:",
               "-C",
               destination,
               "submodule",
               "update",
               "--init",
               "--recursive",
               "--depth",
               "1",
               submodule_path
             ],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          {:cont, :ok}

        {output, status} ->
          if private_submodule_error?(output) do
            Logger.info("Skipping private submodule #{submodule_path} for #{full_handle}@#{tag}")
            {:cont, :ok}
          else
            {:halt, {:error, {:git_submodule_failed, status, output}}}
          end
      end
    end)
  end

  defp submodule_paths(destination) do
    gitmodules_path = Path.join(destination, ".gitmodules")

    if File.exists?(gitmodules_path) do
      gitmodules_content = File.read!(gitmodules_path)

      ~r/^\s*path\s*=\s*(.+)\s*$/m
      |> Regex.scan(gitmodules_content)
      |> Enum.map(fn [_, path] -> String.trim(path) end)
    else
      []
    end
  end

  defp private_submodule_error?(output) do
    String.contains?(output, "fatal: could not read Username for")
  end

  defp remove_git_metadata(directory) do
    directory
    |> Path.join("**/.git")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(&File.rm_rf!/1)

    gitmodules_path = Path.join(directory, ".gitmodules")
    if File.exists?(gitmodules_path), do: File.rm(gitmodules_path)
  end

  defp zip_directory(directory, archive_path) do
    parent_dir = Path.dirname(directory)
    base_name = Path.basename(directory)

    case System.cmd("zip", ["--symlinks", "-r", archive_path, base_name], cd: parent_dir) do
      {_, 0} -> :ok
      {output, status} -> {:error, {:zip_failed, status, output}}
    end
  end

  defp upload_source_archive(scope, name, version, archive_path) do
    key = KeyNormalizer.package_object_key(%{scope: scope, name: name}, version: version, path: "source_archive.zip")
    upload_file(key, archive_path, "application/zip")
  end

  defp fetch_and_upload_manifests(scope, name, version, full_handle, tag, token) do
    with {:ok, contents} <- GitHub.list_repository_contents(full_handle, token, tag) do
      manifests =
        contents
        |> Enum.map(&Map.get(&1, "path"))
        |> Enum.filter(&manifest_path?/1)
        |> Enum.map(fn path ->
          filename = Path.basename(path)
          swift_version = manifest_swift_version(filename)

          with {:ok, content} <- GitHub.get_file_content(full_handle, token, path, tag),
               :ok <- upload_manifest(scope, name, version, filename, content) do
            %{
              "swift_version" => swift_version,
              "swift_tools_version" => swift_tools_version(content)
            }
          else
            {:error, reason} ->
              Logger.warning("Failed to fetch manifest #{path} for #{scope}/#{name}@#{tag}: #{inspect(reason)}")
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, manifests}
    end
  end

  defp update_metadata_with_release(scope, name, full_handle, version, checksum, manifests) do
    lock_key = {:package, scope, name}

    case Lock.try_acquire(lock_key, @metadata_lock_ttl_seconds) do
      {:ok, :acquired} ->
        try do
          metadata =
            case Metadata.get_package(scope, name, fresh: true) do
              {:ok, metadata} ->
                metadata

              {:error, :not_found} ->
                %{"scope" => scope, "name" => name, "repository_full_handle" => full_handle, "releases" => %{}}

              {:error, reason} ->
                {:error, reason}
            end

          case metadata do
            {:error, reason} ->
              {:error, reason}

            metadata ->
              updated_metadata =
                metadata
                |> Map.put_new("scope", scope)
                |> Map.put_new("name", name)
                |> Map.put("repository_full_handle", full_handle)
                |> Map.put("updated_at", DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601())
                |> Map.update("releases", %{version => %{"checksum" => checksum, "manifests" => manifests}}, fn releases ->
                  Map.put(releases || %{}, version, %{
                    "checksum" => checksum,
                    "manifests" => manifests
                  })
                end)

              Metadata.put_package(scope, name, updated_metadata)
          end
        after
          Lock.release(lock_key)
        end

      {:error, :already_locked} ->
        {:error, :already_locked}
    end
  end

  defp upload_manifest(scope, name, version, filename, content) do
    key = KeyNormalizer.package_object_key(%{scope: scope, name: name}, version: version, path: filename)
    upload_content(key, content, "text/x-swift")
  end

  defp upload_file(key, path, content_type) do
    bucket = Application.get_env(:cache, :s3)[:bucket]

    case path
         |> ExAws.S3.Upload.stream_file()
         |> ExAws.S3.upload(bucket, key, content_type: content_type, timeout: 120_000)
         |> ExAws.request() do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp upload_content(key, content, content_type) do
    bucket = Application.get_env(:cache, :s3)[:bucket]

    case bucket
         |> ExAws.S3.put_object(key, content, content_type: content_type)
         |> ExAws.request() do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp manifest_path?("Package.swift"), do: true
  defp manifest_path?(path) when is_binary(path), do: Regex.match?(@alternate_manifest_regex, Path.basename(path))
  defp manifest_path?(_), do: false

  defp manifest_swift_version("Package.swift"), do: nil

  defp manifest_swift_version(filename) do
    case Regex.run(@alternate_manifest_regex, filename) do
      [_, major] -> major
      [_, major, minor] -> "#{major}.#{minor}"
      [_, major, minor, patch] -> "#{major}.#{minor}.#{patch}"
      _ -> nil
    end
  end

  defp swift_tools_version(content) do
    case Regex.run(~r/^\/\/ swift-tools-version:\s?(\d+)(?:\.(\d+))?(?:\.(\d+))?/, content) do
      [_, major] -> major
      [_, major, minor] -> "#{major}.#{minor}"
      [_, major, minor, patch] -> "#{major}.#{minor}.#{patch}"
      _ -> nil
    end
  end

  defp checksum_for_file(path) do
    hash =
      path
      |> File.stream!([], 2048)
      |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
        :crypto.hash_update(acc, chunk)
      end)
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    {:ok, hash}
  rescue
    error -> {:error, error}
  end

  defp temp_dir do
    base = System.tmp_dir!()
    unique = :erlang.unique_integer([:positive, :monotonic])
    path = Path.join(base, "tuist-registry-#{unique}")
    File.mkdir_p!(path)
    path
  end

  defp registry_token do
    Application.get_env(:cache, :registry_github_token)
  end
end
