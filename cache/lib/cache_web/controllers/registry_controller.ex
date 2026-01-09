defmodule CacheWeb.RegistryController do
  use CacheWeb, :controller

  alias Cache.Disk
  alias Cache.Registry.KeyNormalizer
  alias Cache.Registry.Metadata
  alias Cache.S3
  alias Cache.S3Transfers

  require Logger

  def availability(conn, _params) do
    conn
    |> put_resp_header("content-version", "1")
    |> send_resp(:ok, "")
  end

  def list_releases(conn, %{"scope" => scope, "name" => name}) do
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
          |> json(%{})
      end
    end
  end

  def download_archive(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    normalized_version = KeyNormalizer.normalize_version(version)

    key =
      KeyNormalizer.package_object_key(%{scope: scope, name: name},
        version: normalized_version,
        path: "source_archive.zip"
      )

    if Disk.registry_exists?(scope, name, normalized_version, "source_archive.zip") do
      local_path = Disk.registry_local_accel_path(scope, name, normalized_version, "source_archive.zip")

      conn
      |> put_resp_header("content-version", "1")
      |> put_resp_header("x-accel-redirect", local_path)
      |> put_resp_content_type("application/zip")
      |> put_resp_header("content-disposition", "attachment; filename=\"#{name}-#{normalized_version}.zip\"")
      |> send_resp(:ok, "")
    else
      S3Transfers.enqueue_registry_download(key)

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
    end
  end

  def show_manifest(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    normalized_version = KeyNormalizer.normalize_version(version)
    swift_version = conn.query_params["swift-version"]

    filename = manifest_filename(swift_version)
    key = KeyNormalizer.package_object_key(%{scope: scope, name: name}, version: normalized_version, path: filename)

    cond do
      Disk.registry_exists?(scope, name, normalized_version, filename) ->
        serve_manifest_from_disk(conn, scope, name, normalized_version, filename, swift_version)

      not is_nil(swift_version) ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(303)
        |> redirect(to: "/api/registry/swift/#{scope}/#{name}/#{normalized_version}/Package.swift")

      true ->
        S3Transfers.enqueue_registry_download(key)

        case S3.presign_download_url(key) do
          {:ok, url} ->
            conn
            |> put_resp_header("content-version", "1")
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
  end

  defp manifest_filename(nil), do: "Package.swift"
  defp manifest_filename(swift_version), do: "Package@swift-#{swift_version}.swift"

  defp serve_manifest_from_disk(conn, scope, name, version, filename, swift_version) do
    local_path = Disk.registry_local_accel_path(scope, name, version, filename)

    conn = put_resp_header(conn, "content-version", "1")

    conn =
      if is_nil(swift_version) do
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
      else
        conn
      end

    conn
    |> put_resp_header("x-accel-redirect", local_path)
    |> put_resp_content_type("text/x-swift")
    |> send_resp(:ok, "")
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
end
