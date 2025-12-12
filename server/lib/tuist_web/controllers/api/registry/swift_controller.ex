defmodule TuistWeb.API.Registry.SwiftController do
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Projects.Project
  alias Tuist.Registry.Swift.Packages
  alias Tuist.Registry.Swift.Packages.Package
  alias Tuist.Registry.Swift.Packages.PackageManifest
  alias Tuist.Registry.Swift.Packages.PackageRelease
  alias Tuist.Storage
  alias Tuist.VCS
  alias TuistWeb.Authentication

  plug(:assign_package when action in [:list_releases, :show_release, :show_package_swift])
  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :registry)

  def availability(conn, _params) do
    conn |> Plug.Conn.send_resp(200, []) |> Plug.Conn.halt()
  end

  def identifiers(conn, %{"url" => repository_url}) do
    with {:ok, :github} <- VCS.get_provider_from_repository_url(repository_url),
         {:ok, full_handle} <- VCS.get_repository_full_handle_from_url(repository_url),
         %{scope: scope, name: name} =
           Packages.get_package_scope_and_name_from_repository_full_handle(full_handle),
         {:ok, _package} <- Packages.get_package_by_scope_and_name(%{scope: scope, name: name}) do
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

  def list_releases(%{assigns: %{package: package}} = conn, _params) do
    payload =
      %{
        releases:
          Map.new(package.package_releases, fn %PackageRelease{version: version} ->
            {version,
             %{
               url: ~p"/api/registry/swift/#{package.scope}/#{package.name}/#{version}"
             }}
          end)
      }

    conn |> put_resp_header("content-version", "1") |> put_status(:ok) |> json(payload)
  end

  def show_release(%{assigns: %{package: package}} = conn, %{"scope" => scope, "name" => name, "version" => version}) do
    if String.ends_with?(version, ".zip") do
      download_release(conn, %{
        "scope" => scope,
        "name" => name,
        "version" => String.trim_trailing(version, ".zip")
      })
    else
      case Packages.get_package_release_by_version(%{
             package: package,
             version: version
           }) do
        nil ->
          conn
          |> put_resp_header("content-version", "1")
          |> put_status(:not_found)
          |> json(%{})

        package_release ->
          conn
          |> put_resp_header("content-version", "1")
          |> json(%{
            id: "#{scope}.#{name}",
            version: package_release.version,
            resources: [
              %{
                name: "source-archive",
                type: "application/zip",
                checksum: package_release.checksum
              }
            ]
          })
      end
    end
  end

  def show_package_swift(
        %{assigns: %{package: package}} = conn,
        %{"scope" => scope, "name" => name, "version" => version} = opts
      ) do
    package_release =
      Packages.get_package_release_by_version(
        %{
          package: package,
          version: version
        },
        preload: [:manifests]
      )

    swift_version = opts["swift-version"]

    object_key =
      package_manifest_object_key(%{
        swift_version: swift_version,
        scope: scope,
        name: name,
        version: version
      })

    if not is_nil(package_release) and not is_nil(object_key) do
      conn = put_resp_header(conn, "content-version", "1")

      conn =
        if is_nil(swift_version) do
          put_resp_header(conn, "link", alternate_manifests_link(package, package_release))
        else
          conn
        end

      conn
      |> put_resp_content_type("text/x-swift")
      |> send_chunked(:ok)
      |> stream_object(object_key)
    else
      if is_nil(swift_version) do
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:not_found)
        |> json(%{})
      else
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(303)
        |> redirect(to: ~p"/api/registry/swift/#{scope}/#{name}/#{version}/Package.swift")
        |> halt()
      end
    end
  end

  defp package_manifest_object_key(%{swift_version: swift_version, scope: scope, name: name, version: version}) do
    if is_nil(swift_version) do
      object_key =
        Packages.package_object_key(%{scope: scope, name: name},
          version: version,
          path: "Package.swift"
        )

      if Storage.object_exists?(object_key, :registry) do
        object_key
      end
    else
      [
        String.replace_trailing(swift_version, ".0.0", ""),
        String.replace_trailing(swift_version, ".0", ""),
        swift_version
      ]
      |> MapSet.new()
      |> Enum.map(
        &Packages.package_object_key(%{scope: scope, name: name},
          version: version,
          path: "Package@swift-#{&1}.swift"
        )
      )
      |> Enum.find(&Storage.object_exists?(&1, :registry))
    end
  end

  defp alternate_manifests_link(%Package{scope: scope, name: name}, %PackageRelease{
         manifests: manifests,
         version: version
       }) do
    manifests
    |> Enum.filter(&(not is_nil(&1.swift_version)))
    |> Enum.map_join(
      ", ",
      fn %PackageManifest{
           swift_version: swift_version,
           swift_tools_version: swift_tools_version
         } ->
        url =
          ~p"/api/registry/swift/#{scope}/#{name}/#{version}/Package.swift?swift-version=#{swift_version}"

        # This is a workaround for: https://github.com/swiftlang/swift-package-manager/pull/8188
        swift_version =
          if swift_version |> String.split(".") |> Enum.count() == 1 do
            swift_version <> ".0"
          else
            swift_version
          end

        Enum.join(
          ["<#{url}>", "rel=\"alternate\"", "filename=\"Package@swift-#{swift_version}.swift\""] ++
            if is_nil(swift_tools_version) do
              []
            else
              ["swift-tools-version=\"#{swift_tools_version}\""]
            end,
          "; "
        )
      end
    )
  end

  def download_release(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    account =
      case Authentication.authenticated_subject(conn) do
        %Project{} = project -> Map.get(project, :account)
        %AuthenticatedAccount{account: account} -> account
        _ -> nil
      end

    object_key =
      Packages.package_object_key(%{scope: scope, name: name},
        version: version,
        path: "source_archive.zip"
      )

    with {:ok, package} <- Packages.get_package_by_scope_and_name(%{scope: scope, name: name}),
         true <- Storage.object_exists?(object_key, :registry) do
      :telemetry.execute(
        [:analytics, :registry, :swift, :source_archive_download],
        %{},
        %{}
      )

      package_release =
        Packages.get_package_release_by_version(%{package: package, version: version})

      if account do
        Packages.create_package_download_event(%{
          package_release: package_release,
          account: account
        })
      end

      conn
      |> put_resp_header("content-version", "1")
      |> put_resp_content_type("application/zip")
      |> put_resp_header(
        "content-disposition",
        "attachment; filename=\"#{name}-#{version}.zip\""
      )
      |> send_chunked(:ok)
      |> stream_object(object_key)
    else
      _ ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:not_found)
        |> json(%{})
    end
  end

  defp stream_object(conn, object_key) do
    object_key
    |> Storage.stream_object(:registry)
    |> Enum.reduce_while(conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end

  defp assign_package(%{params: %{"scope" => scope, "name" => name}} = conn, _opts) do
    case Packages.get_package_by_scope_and_name(%{scope: scope, name: name},
           preload: [:package_releases]
         ) do
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The package #{scope}/#{name} was not found in the registry."})
        |> halt()

      {:ok, package} ->
        assign(conn, :package, package)
    end
  end

  def login(conn, _opts) do
    conn
    |> put_resp_header("content-version", "1")
    |> put_status(:ok)
    |> json(%{})
  end
end
