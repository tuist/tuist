defmodule CacheWeb.RegistryController do
  use CacheWeb, :controller

  alias Cache.CacheArtifacts
  alias Cache.Config
  alias Cache.Registry
  alias Cache.Registry.AlternateManifests
  alias Cache.Registry.EventsPipeline
  alias Cache.Registry.KeyNormalizer
  alias Cache.Registry.Metadata
  alias Cache.Registry.RepositoryURL
  alias Cache.S3
  alias Cache.S3Transfers
  alias CacheWeb.API.Schemas.SafePathComponent

  plug :ensure_registry_enabled

  defp ensure_registry_enabled(conn, _opts) do
    if Config.registry_enabled?() do
      conn
    else
      conn
      |> put_resp_header("content-version", "1")
      |> put_status(:not_found)
      |> json(%{message: "Registry is not available on this cache node."})
      |> halt()
    end
  end

  def availability(conn, _params) do
    conn
    |> put_resp_header("content-version", "1")
    |> send_resp(:ok, "")
  end

  def identifiers(conn, %{"url" => repository_url}) do
    with {:ok, :github} <- provider_from_repository_url(repository_url),
         {:ok, full_handle} <- repository_full_handle_from_url(repository_url),
         {:ok, %{scope: scope, name: name}} <- scope_name_from_full_handle(full_handle),
         {:ok, _metadata} <- Metadata.get_package(scope, name) do
      conn
      |> put_resp_header("content-version", "1")
      |> json(%{identifiers: ["#{scope}.#{name}"]})
    else
      {:error, :invalid_path_params} ->
        invalid_path_params_response(conn)

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

      {:error, {:s3_error, _reason}} ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:service_unavailable)
        |> json(%{message: "Registry is temporarily unavailable. Please try again later."})
    end
  end

  def login(conn, _params) do
    conn
    |> put_resp_header("content-version", "1")
    |> put_status(:ok)
    |> json(%{})
  end

  def list_releases(conn, %{"scope" => scope, "name" => name}) do
    case normalize_registry_scope_name(scope, name) do
      {:ok, {scope, name}} ->
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

          {:error, {:s3_error, _reason}} ->
            conn
            |> put_resp_header("content-version", "1")
            |> put_status(:service_unavailable)
            |> json(%{message: "Registry is temporarily unavailable. Please try again later."})
        end

      {:error, :invalid_path_params} ->
        invalid_path_params_response(conn)
    end
  end

  def show_release(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    case normalize_registry_scope_name(scope, name) do
      {:ok, {scope, name}} ->
        do_show_release(conn, scope, name, version)

      {:error, :invalid_path_params} ->
        invalid_path_params_response(conn)
    end
  end

  def download_archive(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    case normalize_registry_scope_name_version(scope, name, version) do
      {:ok, {scope, name, normalized_version}} ->
        do_download_archive(conn, scope, name, normalized_version)

      {:error, :invalid_path_params} ->
        invalid_path_params_response(conn)
    end
  end

  def show_manifest(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    case normalize_registry_scope_name_version(scope, name, version) do
      {:ok, {scope, name, normalized_version}} ->
        swift_version = conn.query_params["swift-version"]

        swift_version
        |> manifest_candidates()
        |> Enum.reduce_while(:not_found, fn filename, _acc ->
          key =
            KeyNormalizer.package_object_key(%{scope: scope, name: name}, version: normalized_version, path: filename)

          cond do
            Registry.Disk.exists?(scope, name, normalized_version, filename) ->
              {:halt,
               {:served, serve_manifest_from_disk(conn, scope, name, normalized_version, filename, swift_version, key)}}

            S3.exists?(key, type: :registry) ->
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

      {:error, :invalid_path_params} ->
        invalid_path_params_response(conn)
    end
  end

  defp do_show_release(conn, scope, name, version) do
    if String.ends_with?(version, ".zip") do
      download_archive(conn, %{
        "scope" => scope,
        "name" => name,
        "version" => String.trim_trailing(version, ".zip")
      })
    else
      render_release_metadata(conn, scope, name, version)
    end
  end

  defp render_release_metadata(conn, scope, name, version) do
    with {:ok, normalized_version} <- normalize_registry_version(version),
         {:ok, metadata} <- Metadata.get_package(scope, name) do
      render_release_response(conn, scope, name, normalized_version, metadata)
    else
      {:error, :invalid_path_params} ->
        invalid_path_params_response(conn)

      {:error, :not_found} ->
        package_not_found_response(conn, scope, name)

      {:error, {:s3_error, _reason}} ->
        service_unavailable_response(conn)
    end
  end

  defp render_release_response(conn, scope, name, normalized_version, metadata) do
    releases = metadata["releases"] || %{}

    case Map.get(releases, normalized_version) do
      nil ->
        registry_not_found_response(conn)

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
  end

  defp do_download_archive(conn, scope, name, normalized_version) do
    key =
      KeyNormalizer.package_object_key(%{scope: scope, name: name},
        version: normalized_version,
        path: "source_archive.zip"
      )

    if Registry.Disk.exists?(scope, name, normalized_version, "source_archive.zip") do
      track_registry_download(scope, name, normalized_version, key)
      render_local_archive(conn, scope, name, normalized_version)
    else
      render_remote_archive(conn, scope, name, normalized_version, key)
    end
  end

  defp render_local_archive(conn, scope, name, normalized_version) do
    local_path = Registry.Disk.local_accel_path(scope, name, normalized_version, "source_archive.zip")

    conn
    |> put_resp_header("content-version", "1")
    |> put_resp_header("x-accel-redirect", local_path)
    |> put_resp_content_type("application/zip")
    |> put_resp_header("content-disposition", "attachment; filename=\"#{name}-#{normalized_version}.zip\"")
    |> send_resp(:ok, "")
  end

  defp render_remote_archive(conn, scope, name, normalized_version, key) do
    if S3.exists?(key, type: :registry) do
      S3Transfers.enqueue_registry_download(key)
      track_registry_download(scope, name, normalized_version, key)

      case S3.presign_download_url(key, type: :registry) do
        {:ok, url} ->
          conn
          |> put_resp_header("content-version", "1")
          |> put_resp_header("x-accel-redirect", S3.remote_accel_path(url))
          |> put_resp_content_type("application/zip")
          |> put_resp_header("content-disposition", "attachment; filename=\"#{name}-#{normalized_version}.zip\"")
          |> send_resp(:ok, "")

        {:error, _reason} ->
          registry_not_found_response(conn)
      end
    else
      registry_not_found_response(conn)
    end
  end

  defp track_registry_download(scope, name, normalized_version, key) do
    :ok = CacheArtifacts.track_artifact_access(key)

    if Config.analytics_enabled?() do
      EventsPipeline.async_push(%{
        scope: scope,
        name: name,
        version: normalized_version
      })
    end
  end

  defp serve_manifest_from_disk(conn, scope, name, version, filename, swift_version, key) do
    :ok = CacheArtifacts.track_artifact_access(key)
    local_path = Registry.Disk.local_accel_path(scope, name, version, filename)

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

    case S3.presign_download_url(key, type: :registry) do
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
    manifests = manifests_for_link_header(scope, name, version)
    put_alternate_manifest_link(conn, scope, name, version, manifests)
  end

  defp manifests_for_link_header(scope, name, version) do
    metadata_manifests =
      case Metadata.get_package(scope, name) do
        {:ok, metadata} ->
          metadata["releases"]
          |> Kernel.||(%{})
          |> Map.get(version, %{})
          |> Map.get("manifests")

        _ ->
          nil
      end

    if is_list(metadata_manifests) and metadata_manifests != [] do
      metadata_manifests
    else
      AlternateManifests.list(scope, name, version)
    end
  end

  defp put_alternate_manifest_link(conn, _scope, _name, _version, []), do: conn

  defp put_alternate_manifest_link(conn, scope, name, version, manifests) do
    case build_alternate_manifests_link(scope, name, version, manifests) do
      "" -> conn
      link_header -> put_resp_header(conn, "link", link_header)
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
    |> RepositoryURL.normalize_git_url()
    |> URI.parse()
    |> Map.get(:host)
    |> case do
      "github.com" -> {:ok, :github}
      _ -> {:error, :unsupported_vcs}
    end
  end

  defp repository_full_handle_from_url(repository_url) do
    RepositoryURL.repository_full_handle_from_url(repository_url)
  end

  defp invalid_path_params_response(conn) do
    conn
    |> put_resp_header("content-version", "1")
    |> put_status(:bad_request)
    |> json(%{message: "Invalid path parameters."})
  end

  defp package_not_found_response(conn, scope, name) do
    conn
    |> put_resp_header("content-version", "1")
    |> put_status(:not_found)
    |> json(%{message: "The package #{scope}/#{name} was not found in the registry."})
  end

  defp registry_not_found_response(conn) do
    conn
    |> put_resp_header("content-version", "1")
    |> put_status(:not_found)
    |> json(%{})
  end

  defp service_unavailable_response(conn) do
    conn
    |> put_resp_header("content-version", "1")
    |> put_status(:service_unavailable)
    |> json(%{message: "Registry is temporarily unavailable. Please try again later."})
  end

  defp normalize_registry_scope_name(scope, name) do
    {scope, name} = KeyNormalizer.normalize_scope_name(scope, name)

    if SafePathComponent.valid_all?([scope, name]) do
      {:ok, {scope, name}}
    else
      {:error, :invalid_path_params}
    end
  end

  defp normalize_registry_scope_name_version(scope, name, version) do
    with {:ok, {scope, name}} <- normalize_registry_scope_name(scope, name),
         {:ok, normalized_version} <- normalize_registry_version(version) do
      {:ok, {scope, name, normalized_version}}
    end
  end

  defp normalize_registry_version(version) do
    normalized_version = KeyNormalizer.normalize_version(version)

    if SafePathComponent.valid?(normalized_version) do
      {:ok, normalized_version}
    else
      {:error, :invalid_path_params}
    end
  end

  defp scope_name_from_full_handle(repository_full_handle) do
    [scope, name] = String.split(repository_full_handle, "/")

    with {:ok, {scope, name}} <- normalize_registry_scope_name(scope, name) do
      {:ok, %{scope: scope, name: name}}
    end
  end
end
