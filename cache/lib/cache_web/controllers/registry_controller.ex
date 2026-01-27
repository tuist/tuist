defmodule CacheWeb.RegistryController do
  use CacheWeb, :controller

  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.Registry.KeyNormalizer
  alias Cache.Registry.Metadata
  alias Cache.S3
  alias Cache.S3Transfers

  def availability(conn, _params) do
    conn
    |> put_resp_header("content-version", "1")
    |> send_resp(:ok, "")
  end

  def identifiers(conn, %{"url" => repository_url}) do
    with {:ok, :github} <- provider_from_repository_url(repository_url),
         {:ok, full_handle} <- repository_full_handle_from_url(repository_url),
         %{scope: scope, name: name} <- scope_name_from_full_handle(full_handle),
         {:ok, _metadata} <- Metadata.get_package(scope, name) do
      conn
      |> put_resp_header("content-version", "1")
      |> json(%{identifiers: ["#{scope}.#{name}"]})
    else
      {:error, :invalid_repository_url} ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:bad_request)
        |> json(%{message: "Invalid repository URL: #{repository_url}"})

      {:error, :unsupported_vcs} ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:not_found)
        |> json(%{message: "The package #{repository_url} was not found in the registry."})

      {:error, :not_found} ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:not_found)
        |> json(%{message: "The package #{repository_url} was not found in the registry."})
    end
  end

  def login(conn, _params) do
    conn
    |> put_resp_header("content-version", "1")
    |> put_status(:ok)
    |> json(%{})
  end

  def list_releases(conn, %{"scope" => scope, "name" => name}) do
    {scope, name} = normalize_scope_name(scope, name)

    case Metadata.get_package(scope, name) do
      {:ok, metadata} ->
        releases =
          Map.new(metadata["releases"] || %{}, fn {version, _release_data} ->
            {version, %{url: "/api/registry/swift/#{scope}/#{name}/#{version}"}}
          end)

        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:ok)
        |> json(%{releases: releases})

      {:error, :not_found} ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:not_found)
        |> json(%{message: "The package #{scope}/#{name} was not found in the registry."})
    end
  end

  def show_release(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    {scope, name} = normalize_scope_name(scope, name)

    if String.ends_with?(version, ".zip") do
      download_archive(conn, %{
        "scope" => scope,
        "name" => name,
        "version" => String.trim_trailing(version, ".zip")
      })
    else
      case Metadata.get_package(scope, name) do
        {:ok, metadata} ->
          normalized_version = KeyNormalizer.normalize_version(version)
          releases = metadata["releases"] || %{}

          case Map.get(releases, normalized_version) do
            nil ->
              conn
              |> put_resp_header("content-version", "1")
              |> put_status(:not_found)
              |> json(%{})

            release_data ->
              conn
              |> put_resp_header("content-version", "1")
              |> json(%{
                id: "#{scope}.#{name}",
                version: normalized_version,
                resources: [
                  %{
                    name: "source-archive",
                    type: "application/zip",
                    checksum: release_data["checksum"]
                  }
                ]
              })
          end

        {:error, :not_found} ->
          conn
          |> put_resp_header("content-version", "1")
          |> put_status(:not_found)
          |> json(%{message: "The package #{scope}/#{name} was not found in the registry."})
      end
    end
  end

  def download_archive(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    {scope, name} = normalize_scope_name(scope, name)
    normalized_version = KeyNormalizer.normalize_version(version)

    key =
      KeyNormalizer.package_object_key(%{scope: scope, name: name},
        version: normalized_version,
        path: "source_archive.zip"
      )

    if Disk.registry_exists?(scope, name, normalized_version, "source_archive.zip") do
      :ok = CacheArtifacts.track_artifact_access(key)
      local_path = Disk.registry_local_accel_path(scope, name, normalized_version, "source_archive.zip")

      conn
      |> put_resp_header("content-version", "1")
      |> put_resp_header("x-accel-redirect", local_path)
      |> put_resp_content_type("application/zip")
      |> put_resp_header("content-disposition", "attachment; filename=\"#{name}-#{normalized_version}.zip\"")
      |> send_resp(:ok, "")
    else
      if S3.exists?(key) do
        S3Transfers.enqueue_registry_download(key)
        :ok = CacheArtifacts.track_artifact_access(key)

        case S3.presign_download_url(key) do
          {:ok, url} ->
            conn
            |> put_resp_header("content-version", "1")
            |> put_resp_header("x-accel-redirect", S3.remote_accel_path(url))
            |> put_resp_content_type("application/zip")
            |> put_resp_header("content-disposition", "attachment; filename=\"#{name}-#{normalized_version}.zip\"")
            |> send_resp(:ok, "")

          {:error, _reason} ->
            conn
            |> put_resp_header("content-version", "1")
            |> put_status(:not_found)
            |> json(%{})
        end
      else
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:not_found)
        |> json(%{})
      end
    end
  end

  def show_manifest(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    {scope, name} = normalize_scope_name(scope, name)
    normalized_version = KeyNormalizer.normalize_version(version)
    swift_version = conn.query_params["swift-version"]

    swift_version
    |> manifest_candidates()
    |> Enum.reduce_while(:not_found, fn filename, _acc ->
      key = KeyNormalizer.package_object_key(%{scope: scope, name: name}, version: normalized_version, path: filename)

      cond do
        Disk.registry_exists?(scope, name, normalized_version, filename) ->
          {:halt,
           {:served, serve_manifest_from_disk(conn, scope, name, normalized_version, filename, swift_version, key)}}

        S3.exists?(key) ->
          {:halt,
           {:served, serve_manifest_from_s3(conn, scope, name, normalized_version, filename, swift_version, key)}}

        true ->
          {:cont, :not_found}
      end
    end)
    |> case do
      {:served, conn} ->
        conn

      :not_found ->
        if is_nil(swift_version) do
          conn
          |> put_resp_header("content-version", "1")
          |> put_status(:not_found)
          |> json(%{})
        else
          conn
          |> put_resp_header("content-version", "1")
          |> put_status(303)
          |> redirect(to: "/api/registry/swift/#{scope}/#{name}/#{normalized_version}/Package.swift")
        end
    end
  end

  defp serve_manifest_from_disk(conn, scope, name, version, filename, swift_version, key) do
    :ok = CacheArtifacts.track_artifact_access(key)
    local_path = Disk.registry_local_accel_path(scope, name, version, filename)

    conn
    |> put_resp_header("content-version", "1")
    |> maybe_put_alternate_manifest_link(scope, name, version, swift_version)
    |> put_resp_header("x-accel-redirect", local_path)
    |> put_resp_content_type("text/x-swift")
    |> send_resp(:ok, "")
  end

  defp serve_manifest_from_s3(conn, scope, name, version, _filename, swift_version, key) do
    S3Transfers.enqueue_registry_download(key)
    :ok = CacheArtifacts.track_artifact_access(key)

    case S3.presign_download_url(key) do
      {:ok, url} ->
        conn
        |> put_resp_header("content-version", "1")
        |> maybe_put_alternate_manifest_link(scope, name, version, swift_version)
        |> put_resp_header("x-accel-redirect", S3.remote_accel_path(url))
        |> put_resp_content_type("text/x-swift")
        |> send_resp(:ok, "")

      {:error, _reason} ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:not_found)
        |> json(%{})
    end
  end

  defp maybe_put_alternate_manifest_link(conn, _scope, _name, _version, swift_version) when not is_nil(swift_version) do
    conn
  end

  defp maybe_put_alternate_manifest_link(conn, scope, name, version, nil) do
    case Metadata.get_package(scope, name) do
      {:ok, metadata} ->
        releases = metadata["releases"] || %{}

        case Map.get(releases, version) do
          %{"manifests" => manifests} when is_list(manifests) ->
            link_header = build_alternate_manifests_link(scope, name, version, manifests)

            if link_header == "" do
              conn
            else
              put_resp_header(conn, "link", link_header)
            end

          _ ->
            conn
        end

      _ ->
        conn
    end
  end

  defp manifest_candidates(nil), do: ["Package.swift"]

  defp manifest_candidates(swift_version) do
    swift_version
    |> swift_version_candidates()
    |> Enum.map(&"Package@swift-#{&1}.swift")
  end

  defp swift_version_candidates(swift_version) do
    Enum.uniq([
      String.replace_trailing(swift_version, ".0.0", ""),
      String.replace_trailing(swift_version, ".0", ""),
      swift_version
    ])
  end

  defp build_alternate_manifests_link(scope, name, version, manifests) do
    manifests
    |> Enum.filter(fn manifest -> not is_nil(manifest["swift_version"]) end)
    |> Enum.map_join(", ", fn manifest ->
      swift_version = manifest["swift_version"]
      swift_tools_version = manifest["swift_tools_version"]

      url = "/api/registry/swift/#{scope}/#{name}/#{version}/Package.swift?swift-version=#{swift_version}"

      display_version =
        if swift_version |> String.split(".") |> Enum.count() == 1 do
          swift_version <> ".0"
        else
          swift_version
        end

      parts = [
        "<#{url}>",
        "rel=\"alternate\"",
        "filename=\"Package@swift-#{display_version}.swift\""
      ]

      parts =
        if is_nil(swift_tools_version) do
          parts
        else
          parts ++ ["swift-tools-version=\"#{swift_tools_version}\""]
        end

      Enum.join(parts, "; ")
    end)
  end

  defp provider_from_repository_url(repository_url) do
    repository_url
    |> normalize_git_url()
    |> URI.parse()
    |> Map.get(:host)
    |> case do
      "github.com" -> {:ok, :github}
      _ -> {:error, :unsupported_vcs}
    end
  end

  defp repository_full_handle_from_url(repository_url) do
    full_handle =
      repository_url
      |> normalize_git_url()
      |> URI.parse()
      |> Map.get(:path)
      |> String.replace_leading("/", "")
      |> String.replace_trailing("/", "")
      |> String.replace_trailing(".git", "")

    if full_handle |> String.split("/") |> Enum.count() == 2 do
      {:ok, full_handle}
    else
      {:error, :invalid_repository_url}
    end
  end

  defp normalize_git_url(repository_url) do
    Regex.replace(~r/^git@(.+):/, repository_url, "https://\\1/")
  end

  defp scope_name_from_full_handle(repository_full_handle) do
    [scope, name] = String.split(repository_full_handle, "/")

    %{
      scope: String.downcase(scope),
      name: name |> String.replace(".", "_") |> String.downcase()
    }
  end

  defp normalize_scope_name(scope, name) do
    {String.downcase(scope), name |> String.replace(".", "_") |> String.downcase()}
  end
end
