defmodule TuistRegistryWeb.Swift.RegistryController do
  use TuistRegistryWeb, :controller

  alias TuistCommon.Registry.Swift.AlternateManifest
  alias TuistCommon.Registry.Swift.KeyNormalizer
  alias TuistCommon.Registry.Swift.RepositoryURL
  alias TuistRegistry.Config
  alias TuistRegistry.S3
  alias TuistRegistry.Swift.AlternateManifests
  alias TuistRegistry.Swift.Metadata
  alias TuistRegistryWeb.API.Schemas.SafePathComponent

  require Logger

  @registry_base_path "/swift"

  plug(:ensure_registry_enabled)

  defp ensure_registry_enabled(conn, _opts) do
    if Config.registry_enabled?() do
      conn
    else
      conn
      |> put_resp_header("content-version", "1")
      |> put_status(:not_found)
      |> json(%{message: "Registry is not available on this node."})
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
                {version, %{url: registry_path(conn, "/#{scope}/#{name}/#{version}")}}
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

        case locate_manifest(scope, name, normalized_version, swift_version) do
          {:ok, body} ->
            serve_manifest(conn, scope, name, normalized_version, swift_version, body)

          :not_found when is_nil(swift_version) ->
            conn
            |> put_resp_header("content-version", "1")
            |> put_status(:not_found)
            |> json(%{})

          :not_found ->
            conn
            |> put_resp_header("content-version", "1")
            |> put_status(303)
            |> redirect(to: registry_path(conn, "/#{scope}/#{name}/#{normalized_version}/Package.swift"))
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

    if S3.exists?(key, type: :registry) do
      if not head_request?(conn) do
        :telemetry.execute([:tuist_registry, :swift, :download], %{count: 1}, %{
          scope: scope,
          name: name
        })
      end

      case S3.presign_download_url(key, type: :registry) do
        {:ok, url} ->
          conn
          |> put_resp_header("content-version", "1")
          |> put_status(:see_other)
          |> redirect(external: url)

        {:error, _reason} ->
          registry_not_found_response(conn)
      end
    else
      registry_not_found_response(conn)
    end
  end

  defp locate_manifest(scope, name, normalized_version, swift_version) do
    swift_version
    |> manifest_candidates()
    |> Enum.reduce_while(:not_found, fn filename, _acc ->
      key =
        KeyNormalizer.package_object_key(%{scope: scope, name: name},
          version: normalized_version,
          path: filename
        )

      case S3.get_object(key, type: :registry) do
        {:ok, body} -> {:halt, {:ok, body}}
        {:error, _reason} -> {:cont, :not_found}
      end
    end)
  end

  defp serve_manifest(conn, scope, name, normalized_version, nil = _swift_version, body) do
    if not head_request?(conn) do
      :telemetry.execute([:tuist_registry, :swift, :manifest], %{count: 1}, %{
        scope: scope,
        name: name
      })
    end

    conn
    |> put_resp_header("content-version", "1")
    |> put_alternate_manifest_link(scope, name, normalized_version)
    |> put_resp_content_type("text/x-swift")
    |> send_resp(:ok, body)
  end

  defp serve_manifest(conn, scope, name, _normalized_version, _swift_version, body) do
    if not head_request?(conn) do
      :telemetry.execute([:tuist_registry, :swift, :manifest], %{count: 1}, %{
        scope: scope,
        name: name
      })
    end

    conn
    |> put_resp_header("content-version", "1")
    |> put_resp_content_type("text/x-swift")
    |> send_resp(:ok, body)
  end

  defp put_alternate_manifest_link(conn, scope, name, version) do
    manifests = manifests_for_link_header(scope, name, version)

    case build_alternate_manifests_link(conn, scope, name, version, manifests) do
      "" -> conn
      link_header -> put_resp_header(conn, "link", link_header)
    end
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

  defp manifest_candidates(nil), do: ["Package.swift"]

  defp manifest_candidates(swift_version) do
    swift_version
    |> swift_version_candidates()
    |> Enum.map(&"Package@swift-#{&1}.swift")
  end

  defp swift_version_candidates(swift_version) do
    Enum.uniq([
      swift_version,
      strip_suffix_once(swift_version, ".0"),
      strip_suffix_once(swift_version, ".0.0")
    ])
  end

  defp strip_suffix_once(string, suffix) do
    if String.ends_with?(string, suffix) do
      binary_part(string, 0, byte_size(string) - byte_size(suffix))
    else
      string
    end
  end

  defp build_alternate_manifests_link(conn, scope, name, version, manifests) do
    manifests
    |> AlternateManifest.linkable_alternates()
    |> Enum.map_join(", ", fn manifest ->
      swift_version = manifest["swift_version"]
      swift_tools_version = manifest["swift_tools_version"]

      url =
        registry_path(conn, "/#{scope}/#{name}/#{version}/Package.swift?swift-version=#{swift_version}")

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

  defp registry_path(conn, suffix) do
    base = Map.get(conn.assigns, :registry_base_path, @registry_base_path)
    base <> suffix
  end

  defp head_request?(conn) do
    conn.method == "HEAD"
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

    if SafePathComponent.valid?(normalized_version) and
         KeyNormalizer.valid_storage_version?(normalized_version) do
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
