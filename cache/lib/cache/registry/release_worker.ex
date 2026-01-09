defmodule Cache.Registry.ReleaseWorker do
  @moduledoc """
  Oban worker that syncs individual package releases from the server.

  Enqueued by `SyncWorker` for each package. Downloads source archives and
  Package.swift manifests to local disk, then enqueues S3 uploads via
  `S3Transfers.enqueue_registry_upload/1`.

  ## Algorithm

  1. Fetch release metadata from server API
  2. For each release version:
     a. Download source_archive.zip to disk
     b. Download Package.swift manifests to disk
     c. Enqueue S3 upload for each file
  """

  use Oban.Worker, queue: :registry_sync

  alias Cache.Disk
  alias Cache.Registry.KeyNormalizer
  alias Cache.S3Transfers

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"scope" => scope, "name" => name}}) do
    case fetch_package_releases(scope, name) do
      {:ok, releases} ->
        sync_releases(scope, name, releases)
        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch releases for #{scope}/#{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_package_releases(scope, name) do
    server_url = server_url()
    url = "#{server_url}/api/registry/swift/packages/#{scope}/#{name}/releases"

    case Req.get(url, receive_timeout: 60_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        releases = Map.get(body, "releases", Map.get(body, "data", []))
        {:ok, releases}

      {:ok, %Req.Response{status: 404}} ->
        {:ok, []}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_releases(scope, name, releases) do
    Enum.each(releases, fn release ->
      version = release["version"]

      if version do
        sync_release(scope, name, version, release)
      else
        Logger.warning("Skipping release with missing version: #{inspect(release)}")
      end
    end)
  end

  defp sync_release(scope, name, version, release) do
    download_source_archive(scope, name, version, release)
    download_manifests(scope, name, version, release)
  end

  defp download_source_archive(scope, name, version, release) do
    source_archive_url = release["source_archive_url"]

    if source_archive_url do
      key =
        KeyNormalizer.package_object_key(
          %{scope: scope, name: name},
          version: version,
          path: "source_archive.zip"
        )

      case download_to_disk(source_archive_url, key) do
        :ok ->
          S3Transfers.enqueue_registry_upload(key)
          Logger.debug("Downloaded and enqueued source archive for #{scope}/#{name}@#{version}")

        {:error, :exists} ->
          S3Transfers.enqueue_registry_upload(key)
          Logger.debug("Source archive already exists for #{scope}/#{name}@#{version}")

        {:error, reason} ->
          Logger.warning("Failed to download source archive for #{scope}/#{name}@#{version}: #{inspect(reason)}")
      end
    end
  end

  defp download_manifests(scope, name, version, release) do
    manifests = release["manifests"] || []

    Enum.each(manifests, fn manifest ->
      swift_version = manifest["swift_version"]
      manifest_url = manifest["url"]

      if manifest_url do
        filename = manifest_filename(swift_version)

        key =
          KeyNormalizer.package_object_key(
            %{scope: scope, name: name},
            version: version,
            path: filename
          )

        case download_to_disk(manifest_url, key) do
          :ok ->
            S3Transfers.enqueue_registry_upload(key)
            Logger.debug("Downloaded and enqueued manifest #{filename} for #{scope}/#{name}@#{version}")

          {:error, :exists} ->
            S3Transfers.enqueue_registry_upload(key)
            Logger.debug("Manifest #{filename} already exists for #{scope}/#{name}@#{version}")

          {:error, reason} ->
            Logger.warning(
              "Failed to download manifest #{filename} for #{scope}/#{name}@#{version}: #{inspect(reason)}"
            )
        end
      end
    end)
  end

  defp manifest_filename(nil), do: "Package.swift"
  defp manifest_filename(swift_version), do: "Package@swift-#{swift_version}.swift"

  defp download_to_disk(url, key) do
    path = Disk.artifact_path(key)

    if File.exists?(path) do
      {:error, :exists}
    else
      tmp_path = path <> ".tmp.#{:erlang.unique_integer([:positive])}"

      case download_file(url, tmp_path) do
        :ok ->
          finalize_download(tmp_path, path)

        {:error, reason} ->
          File.rm(tmp_path)
          {:error, reason}
      end
    end
  end

  defp download_file(url, tmp_path) do
    dir = Path.dirname(tmp_path)

    with :ok <- File.mkdir_p(dir) do
      case Req.get(url, receive_timeout: 120_000) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          File.write(tmp_path, body)

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp finalize_download(tmp_path, path) do
    case File.rename(tmp_path, path) do
      :ok ->
        :ok

      {:error, :eexist} ->
        File.rm(tmp_path)
        {:error, :exists}

      {:error, reason} ->
        File.rm(tmp_path)
        {:error, reason}
    end
  end

  defp server_url do
    Application.get_env(:cache, :server_url, "http://localhost:4000")
  end
end
