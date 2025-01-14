defmodule Tuist.Registry.Swift.Packages do
  @moduledoc """
  A module for interacting with Swift packages.
  """

  alias Tuist.Registry.Swift.Packages.PackageManifest
  alias Tuist.Zip
  alias Tuist.Crypto
  alias Tuist.VCS.Repositories.Content
  alias Tuist.Registry.Swift.Packages.PackageRelease
  alias Tuist.Registry.Swift.Packages.Package
  alias Tuist.Registry.Swift.Packages.PackageDownloadEvent
  alias Tuist.VCS
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Accounts.Account

  @alternate_package_manifest_regex ~r/\APackage@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?.swift\z/

  def paginated_packages(attrs) do
    Package
    |> Flop.validate_and_run!(attrs, for: Package)
  end

  def create_package(
        %{
          scope: scope,
          name: name,
          repository_full_handle: repository_full_handle
        },
        opts \\ []
      ) do
    %Package{}
    |> Package.create_changeset(%{
      scope: scope,
      name: name,
      repository_full_handle: repository_full_handle,
      inserted_at: Keyword.get(opts, :inserted_at),
      updated_at: Keyword.get(opts, :updated_at),
      last_updated_releases_at: Keyword.get(opts, :last_updated_releases_at)
    })
    |> Repo.insert!()
  end

  def get_package_by_scope_and_name(%{scope: scope, name: name}, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    Package
    |> Repo.get_by(scope: scope, name: name)
    |> Repo.preload(preload)
  end

  def get_package_scope_and_name_from_repository_full_handle(repository_full_handle) do
    [scope, name] = String.split(repository_full_handle, "/")

    %{
      scope: scope,
      name: name |> String.replace(".", "_"),
      repository_full_handle: repository_full_handle
    }
  end

  def create_missing_package_releases(%{
        package:
          %Package{repository_full_handle: repository_full_handle} =
            package,
        token: token
      }) do
    package = package |> Repo.preload(:package_releases)

    VCS.get_tags(%{
      repository_full_handle: repository_full_handle,
      provider: :github,
      token: token
    })
    |> Enum.map(& &1.name)
    |> Enum.filter(fn version ->
      # Matches semantic version as per: https://semver.org/
      # Examples: 1.0.0, 1.0.0-alpha, 1.0.0-alpha.1
      Regex.match?(~r/^v?\d+\.\d+\.\d+[0-9A-Za-z-]*(\.[0-9A-Za-z]*)?$/, version) and
        not Enum.any?(package.package_releases, &(&1.version == semantic_version(version)))
    end)
    |> Enum.uniq_by(&semantic_version(&1))
    |> Enum.map(fn version ->
      create_package_release(%{
        package: package,
        version: version,
        token: token
      })
    end)
  end

  defp semantic_version(version) do
    version =
      version
      |> String.trim_leading("v")

    case String.split(version, "-") do
      [version, pre_release] ->
        # SwiftPM expects between pre-release and build identifier a plus instead of a dot
        # Semantic version: 1.0.0-alpha.1
        # SwiftPM version: 1.0.0-alpha+1
        pre_release_with_replaced_dot = String.replace(pre_release, ".", "+")
        "#{version}-#{pre_release_with_replaced_dot}"

      _ ->
        version
    end
  end

  def create_package_release(%{
        package:
          %Package{
            id: package_id,
            scope: scope,
            name: name,
            repository_full_handle: repository_full_handle
          } = package,
        version: version,
        token: token
      }) do
    {:ok, file_list} =
      VCS.get_source_archive_by_tag_and_repository_full_handle(%{
        provider: :github,
        repository_full_handle: repository_full_handle,
        tag: version,
        token: token
      })

    file_list =
      file_list
      |> Enum.filter(fn file_tuple ->
        # Filter out directories to fix swift package resolve permission issues.
        # See for more context: https://github.com/tuist/server/pull/1237
        case file_tuple do
          {_, ""} -> false
          _ -> true
        end
      end)
      |> Enum.map(fn {file_name, file_content} ->
        cond do
          # The Swift package manifest needs to be in the root of the repository.
          List.to_string(file_name) |> String.split("/") |> Enum.count() > 2 ->
            {file_name, file_content}

          List.to_string(file_name) |> String.ends_with?("Package.swift") ->
            {file_name,
             replace_package_by_name_references_with_product_in_package_manifest(file_content)}

          Regex.match?(
            @alternate_package_manifest_regex,
            List.to_string(file_name) |> String.split("/") |> List.last()
          ) ->
            {file_name,
             replace_package_by_name_references_with_product_in_package_manifest(file_content)}

          true ->
            {file_name, file_content}
        end
      end)

    {:ok, {_, data}} = Zip.create("source_archive.zip", file_list, [:memory])

    object_key =
      package_object_key(%{scope: scope, name: name},
        version: version,
        path: "source_archive.zip"
      )

    Storage.put_object(object_key, data)

    checksum =
      Crypto.hash_init(:sha256)
      |> Crypto.hash_update(data)
      |> Crypto.hash_final()
      |> Base.encode16()
      |> String.downcase()

    package_release =
      %PackageRelease{}
      |> PackageRelease.create_changeset(%{
        package_id: package_id,
        checksum: checksum,
        version: semantic_version(version)
      })
      |> Repo.insert!()

    create_package_manifests(%{
      package: package,
      token: token,
      reference: version,
      package_release: package_release
    })

    package_release
  end

  defp create_package_manifests(%{
         package:
           %Package{
             repository_full_handle: repository_full_handle
           } = package,
         token: token,
         reference: reference,
         package_release: %PackageRelease{} = package_release
       }) do
    {:ok, root_contents} =
      VCS.get_repository_content(
        %{
          repository_full_handle: repository_full_handle,
          provider: :github,
          token: token
        },
        reference: reference
      )

    root_contents
    |> Enum.each(fn %Content{path: path} ->
      swift_version =
        case Regex.run(@alternate_package_manifest_regex, path) do
          [_, major] -> major
          [_, major, minor] -> "#{major}.#{minor}"
          [_, major, minor, patch] -> "#{major}.#{minor}.#{patch}"
          _ -> nil
        end

      cond do
        path == "Package.swift" ->
          create_package_manifest(%{
            package: package,
            token: token,
            package_release: package_release,
            swift_version: nil,
            path: path,
            reference: reference
          })

        not is_nil(swift_version) ->
          create_package_manifest(%{
            package: package,
            token: token,
            package_release: package_release,
            swift_version: swift_version,
            path: path,
            reference: reference
          })

        true ->
          :ok
      end
    end)
  end

  defp create_package_manifest(%{
         package: %Package{
           scope: scope,
           name: name,
           repository_full_handle: repository_full_handle
         },
         token: token,
         package_release: %PackageRelease{id: package_release_id, version: version},
         swift_version: swift_version,
         path: path,
         reference: reference
       }) do
    {:ok, %Content{content: package_manifest_content}} =
      VCS.get_repository_content(
        %{
          repository_full_handle: repository_full_handle,
          provider: :github,
          token: token
        },
        reference: reference,
        path: path
      )

    Storage.put_object(
      package_object_key(%{scope: scope, name: name}, version: version, path: path),
      package_manifest_content
      |> replace_package_by_name_references_with_product_in_package_manifest()
    )

    swift_tools_version =
      case Regex.run(
             ~r/^\/\/ swift-tools-version:\s?(\d+)(?:\.(\d+))?(?:\.(\d+))?/,
             package_manifest_content
           ) do
        [_, major, minor] -> "#{major}.#{minor}"
        [_, major, minor, patch] -> "#{major}.#{minor}.#{patch}"
        _ -> nil
      end

    %PackageManifest{}
    |> PackageManifest.create_changeset(%{
      package_release_id: package_release_id,
      swift_version: swift_version,
      swift_tools_version: swift_tools_version
    })
    |> Repo.insert!()
  end

  def update_package(%Package{} = package, attrs) do
    package |> Package.update_changeset(attrs) |> Repo.update()
  end

  def get_package_release_by_version(
        %{
          package: %Package{id: package_id},
          version: version
        },
        opts \\ []
      ) do
    preload = Keyword.get(opts, :preload, [])

    PackageRelease
    |> Repo.get_by(package_id: package_id, version: version)
    |> Repo.preload(preload)
  end

  defp replace_package_by_name_references_with_product_in_package_manifest(package_manifest) do
    packages =
      extract_url_only_packages(package_manifest) ++ extract_named_url_packages(package_manifest)

    Enum.reduce(packages, package_manifest, fn package, package_manifest ->
      package_manifest
      |> String.replace(
        ~r/"#{package.by_name_reference}"/is,
        "\"#{package.name}\""
      )
      |> String.replace(
        ~r/(?<![package|name]: )(?<!\()"(#{package.name})"/is,
        ".product(name: \"#{package.name}\", package: \"#{package.name}\")"
      )
      |> String.replace(
        ~r/.byName\(name:\s*"(#{package.name})"\s*\)/is,
        ".product(name: \"#{package.name}\", package: \"#{package.name}\")"
      )
      # Workaround for a bug in SwiftPM fixed in: https://github.com/swiftlang/swift-package-manager/pull/8194
      |> String.replace(
        ~r/package:\s*"#{package.name}"/is,
        "package: \"#{package.name}\""
      )
    end)
  end

  defp extract_url_only_packages(package_manifest) do
    Regex.scan(~r/\.package\(\s*url:\s*"([^"]+)"/, package_manifest)
    |> Enum.map(&List.last/1)
    |> Enum.map(&VCS.get_repository_full_handle_from_url/1)
    |> Enum.filter(&(String.split(&1, "/") |> Enum.count() == 2))
    |> Enum.map(&get_package_scope_and_name_from_repository_full_handle/1)
    |> Enum.map(&%{scope: &1.scope, name: &1.name, by_name_reference: &1.name})
  end

  defp extract_named_url_packages(package_manifest) do
    Regex.scan(~r/\.package\(\s*name:\s*"([^"]+)"\s*,\s*url:\s*"([^"]+)/, package_manifest)
    |> Enum.map(&Enum.slice(&1, -2, 2))
    |> Enum.map(fn [by_name_reference, package_url] ->
      [scope, package_name] =
        VCS.get_repository_full_handle_from_url(package_url)
        |> String.split("/")

      %{scope: scope, name: package_name, by_name_reference: by_name_reference}
    end)
  end

  def package_manifest_as_string(%{scope: scope, name: name, version: version}) do
    object_key =
      package_object_key(%{scope: scope, name: name}, version: version, path: "Package.swift")

    if Storage.object_exists?(object_key) do
      package_manifest =
        Storage.get_object_as_string(object_key)

      packages =
        Regex.scan(~r/url:\s*"([^"]+)"/, package_manifest)
        |> Enum.map(&List.last/1)
        |> Enum.map(&VCS.get_repository_full_handle_from_url/1)
        |> Enum.map(&get_package_scope_and_name_from_repository_full_handle/1)

      package_manifest =
        Enum.reduce(packages, package_manifest, fn package, package_manifest ->
          package_manifest
          |> String.replace(
            ~r/(?<![package|name]: )"(#{package.name})"/i,
            ".product(name: \"#{package.name}\", package: \"#{package.name}\")"
          )
        end)

      {:ok, package_manifest}
    else
      {:error, :not_found}
    end
  end

  def package_object_key(%{scope: scope, name: name}, opts \\ []) do
    version = Keyword.get(opts, :version, nil)
    path = Keyword.get(opts, :path, nil)
    object_key = "registry/swift/#{scope}/#{name}" |> String.downcase()

    object_key =
      if is_nil(version) do
        object_key
      else
        object_key <> "/#{semantic_version(version)}"
      end

    if is_nil(path) do
      object_key
    else
      object_key <> "/#{path}"
    end
  end

  def create_package_download_event(%{
        package_release: %PackageRelease{id: package_release_id},
        account: %Account{id: account_id}
      }) do
    %PackageDownloadEvent{}
    |> PackageDownloadEvent.create_changeset(%{
      package_release_id: package_release_id,
      account_id: account_id
    })
    |> Repo.insert!()
  end
end
