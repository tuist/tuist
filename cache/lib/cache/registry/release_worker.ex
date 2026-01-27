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

      case Metadata.get_package(scope, name) do
        {:ok, metadata} ->
          releases = Map.get(metadata, "releases", %{})

          if Map.has_key?(releases, normalized_version) do
            :ok
          else
            sync_release(scope, name, full_handle, tag, normalized_version, token, metadata)
          end

        {:error, :not_found} ->
          metadata = %{"scope" => scope, "name" => name, "repository_full_handle" => full_handle, "releases" => %{}}
          sync_release(scope, name, full_handle, tag, normalized_version, token, metadata)
      end
    end
  end

  defp sync_release(scope, name, full_handle, tag, version, token, metadata) do
    tmp_dir = temp_dir()
    archive_path = Path.join(tmp_dir, "source_archive.zip")

    try do
      with :ok <- fetch_source_archive(full_handle, tag, token, tmp_dir, archive_path),
           {:ok, checksum} <- checksum_for_file(archive_path),
           :ok <- upload_source_archive(scope, name, version, archive_path),
           {:ok, manifests} <- fetch_and_upload_manifests(scope, name, version, full_handle, tag, token) do
        updated_metadata =
          metadata
          |> Map.put("repository_full_handle", full_handle)
          |> Map.put("updated_at", DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601())
          |> Map.put("releases", Map.put(Map.get(metadata, "releases", %{}), version, %{
            "checksum" => checksum,
            "manifests" => manifests
          }))

        case Metadata.put_package(scope, name, updated_metadata) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
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
      clone_with_submodules(full_handle, tag, token, tmp_dir, archive_path)
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

  defp clone_with_submodules(full_handle, tag, token, tmp_dir, archive_path) do
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
        update_submodules(clone_dest)
        remove_git_metadata(clone_dest)
        zip_directory(clone_dest, archive_path)

      {_output, status} ->
        {:error, {:git_clone_failed, status}}
    end
  end

  defp update_submodules(directory) do
    _ = System.cmd("git", ["submodule", "update", "--init", "--recursive"], cd: directory, stderr_to_stdout: true)
    :ok
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
