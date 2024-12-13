defmodule TuistWeb.API.Registry.SwiftController do
  use TuistWeb, :controller
  import Plug.Conn
  alias Tuist.Registry.Swift.Packages.Package
  alias Tuist.Registry.Swift.Packages.PackageManifest
  alias Tuist.Registry.Swift.Packages.PackageRelease
  alias Tuist.Registry.Swift.Packages
  alias Tuist.VCS
  alias Tuist.Storage

  plug(:assign_package when action in [:list_releases, :show_release, :show_package_swift])
  plug(TuistWeb.API.EnsureAccountPresencePlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :registry)

  def availability(conn, _params) do
    conn |> Plug.Conn.send_resp(200, []) |> Plug.Conn.halt()
  end

  def identifiers(conn, %{"url" => repository_url}) do
    provider =
      VCS.get_provider_from_repository_url(repository_url)

    case provider do
      {:ok, :github} ->
        [scope, name] =
          VCS.get_repository_full_handle_from_url(repository_url)
          |> String.split("/")

        if is_nil(Packages.get_package_by_scope_and_name(%{scope: scope, name: name})) do
          conn
          |> put_resp_header("content-version", "1")
          |> json(%{identifiers: []})
        else
          conn
          |> put_resp_header("content-version", "1")
          |> json(%{identifiers: ["#{scope}.#{name}"]})
        end

      {:error, :unsupported_vcs} ->
        conn
        |> put_resp_header("content-version", "1")
        |> json(%{identifiers: []})
    end
  end

  def list_releases(%{assigns: %{package: package}} = conn, %{"account_handle" => account_handle}) do
    payload =
      %{
        releases:
          package.package_releases
          |> Enum.map(fn %PackageRelease{version: version} ->
            {version,
             %{
               url:
                 ~p"/api/accounts/#{account_handle}/registry/swift/#{package.scope}/#{package.name}/#{version}"
             }}
          end)
          |> Enum.into(%{})
      }

    conn |> put_resp_header("content-version", "1") |> put_status(:ok) |> json(payload)
  end

  def show_release(%{assigns: %{package: package}} = conn, %{
        "scope" => scope,
        "name" => name,
        "version" => version
      }) do
    if version |> String.ends_with?(".zip") do
      download_release(conn, %{
        "scope" => scope,
        "name" => name,
        "version" => version |> String.trim_trailing(".zip")
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
        %{assigns: %{package: package}, params: %{"account_handle" => account_handle}} = conn,
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
      if is_nil(swift_version) do
        "registry/swift/#{scope}/#{name}/#{version}/Package.swift"
      else
        "registry/swift/#{scope}/#{name}/#{version}/Package@swift-#{swift_version}.swift"
      end

    if not is_nil(package_release) and Storage.object_exists?(object_key) do
      conn =
        conn
        |> put_resp_header("content-version", "1")

      conn =
        if is_nil(swift_version) do
          conn
          |> put_resp_header(
            "link",
            alternate_manifests_link(package, package_release)
          )
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
        |> redirect(
          to:
            ~p"/api/accounts/#{account_handle}/registry/swift/#{scope}/#{name}/#{version}/Package.swift"
        )
      end
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
          ~p"/api/accounts/tuist/registry/swift/#{scope}/#{name}/#{version}/Package.swift?swift-version=#{swift_version}"

        ([
           "<#{url}>",
           "rel=\"alternate\"",
           "filename=\"Package@swift-#{swift_version}.swift\""
         ] ++
           if is_nil(swift_tools_version) do
             []
           else
             ["swift-tools-version=\"#{swift_tools_version}\""]
           end)
        |> Enum.join("; ")
      end
    )
  end

  def download_release(conn, %{"scope" => scope, "name" => name, "version" => version}) do
    object_key = "registry/swift/#{scope}/#{name}/#{version}/source_archive.zip"

    if Storage.object_exists?(object_key) do
      conn
      |> put_resp_header("content-version", "1")
      |> put_resp_content_type("application/zip")
      |> put_resp_header("content-disposition", "attachment; filename=\"#{name}-#{version}.zip\"")
      |> send_chunked(:ok)
      |> stream_object(object_key)
    else
      conn
      |> put_resp_header("content-version", "1")
      |> put_status(:not_found)
      |> json(%{})
    end
  end

  defp stream_object(conn, object_key) do
    Storage.stream_object(object_key)
    |> Enum.reduce_while(conn, fn chunk, conn ->
      case chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end

  defp assign_package(
         %{
           params: %{
             "scope" => scope,
             "name" => name
           }
         } = conn,
         _opts
       ) do
    case Packages.get_package_by_scope_and_name(%{scope: scope, name: name},
           preload: [:package_releases]
         ) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "The package #{scope}/#{name} was not found in the registry."})
        |> halt()

      package ->
        conn |> assign(:package, package)
    end
  end

  def login(conn, _opts) do
    conn
    |> put_resp_header("content-version", "1")
    |> put_status(:ok)
    |> json(%{})
  end
end
