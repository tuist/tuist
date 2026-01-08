defmodule Tuist.Registry.Swift.Packages do
  @moduledoc """
  A module for interacting with Swift packages.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Crypto
  alias Tuist.Registry.Swift.Packages.Package
  alias Tuist.Registry.Swift.Packages.PackageDownloadEvent
  alias Tuist.Registry.Swift.Packages.PackageManifest
  alias Tuist.Registry.Swift.Packages.PackageRelease
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.VCS
  alias Tuist.VCS.Repositories.Content

  require Logger

  @alternate_package_manifest_regex ~r/\APackage@swift-(\d+)(?:\.(\d+))?(?:\.(\d+))?.swift\z/

  def paginated_packages(attrs, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    query =
      from p in Package,
        preload: ^preload

    Flop.validate_and_run!(query, attrs, for: Package)
  end

  def create_package(%{scope: scope, name: name, repository_full_handle: repository_full_handle}, opts \\ []) do
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
    |> Repo.preload(Keyword.get(opts, :preload, [:package_releases]))
  end

  def delete_package(%Package{} = package) do
    Repo.delete!(package)
  end

  def all_packages(opts \\ []) do
    preload = Keyword.get(opts, :preload, [])
    Repo.all(from p in Package, preload: ^preload)
  end

  def get_package_by_scope_and_name(%{scope: scope, name: name}, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    case Repo.get_by(Package, scope: scope, name: name) do
      nil -> {:error, :not_found}
      package -> {:ok, Repo.preload(package, preload)}
    end
  end

  def get_packages_by_scope_and_name_pairs(packages, opts \\ []) do
    scope_name_pairs = Enum.map(packages, &{&1.scope, &1.name})

    preload = Keyword.get(opts, :preload, [])

    if Enum.empty?(scope_name_pairs) do
      []
    else
      base_query = from(p in Package)

      query =
        Enum.reduce(scope_name_pairs, base_query, fn {scope, name}, query ->
          or_where(query, [p], p.scope == ^scope and p.name == ^name)
        end)

      query
      |> preload(^preload)
      |> Repo.all()
    end
  end

  def get_package_scope_and_name_from_repository_full_handle(repository_full_handle) do
    [scope, name] = String.split(repository_full_handle, "/")

    %{
      scope: scope,
      name: String.replace(name, ".", "_"),
      repository_full_handle: repository_full_handle
    }
  end

  def get_missing_package_versions(%{
        package: %Package{repository_full_handle: repository_full_handle, scope: scope, name: name} = package,
        token: token
      }) do
    case VCS.get_tags(%{
           repository_full_handle: repository_full_handle,
           provider: :github,
           token: token
         }) do
      {:error, {:http_error, status}} when status in [403, 404] ->
        Logger.debug("Skipping #{scope}/#{name} (#{repository_full_handle}): repository not found or not accessible")
        []

      {:error, {:http_error, status}} ->
        Logger.debug("Skipping #{scope}/#{name} (#{repository_full_handle}): HTTP error #{status}")
        []

      tags ->
        tags
        |> Enum.map(& &1.name)
        |> Enum.filter(fn version ->
          # Matches semantic version as per: https://semver.org/
          # Examples: 1.0.0, 1.0.0-alpha, 1.0.0-alpha.1, 1.1
          # Skip dev versions like 0.9.3-dev1985
          # Skip non-semantic versions like 3.2.0.1 (four-part versions)
          Regex.match?(
            ~r/^v?\d+\.\d+(\.\d+)?(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/,
            version
          ) and
            not Regex.match?(~r/-dev/, version) and
            not Enum.any?(package.package_releases, &(&1.version == semantic_version(version)))
        end)
        |> Enum.uniq_by(&semantic_version(&1))
        |> Enum.map(fn version ->
          %{scope: scope, name: name, version: version}
        end)
    end
  end

  def semantic_version(version) do
    version = String.trim_leading(version, "v")

    case String.split(version, "-") do
      [version, pre_release] ->
        # SwiftPM expects between pre-release and build identifier a plus instead of a dot
        # Semantic version: 1.0.0-alpha.1
        # SwiftPM version: 1.0.0-alpha+1
        pre_release_with_replaced_dot = String.replace(pre_release, ".", "+")
        version = add_trailing_semantic_version_zeros(version)
        "#{version}-#{pre_release_with_replaced_dot}"

      _ ->
        add_trailing_semantic_version_zeros(version)
    end
  end

  # Some versions might not have a minor or patch version, such as 1 or 1.1.
  # In those cases, we can add trailing zeros to make it a valid semantic version.
  defp add_trailing_semantic_version_zeros(version) do
    case String.split(version, ".") do
      [major] -> "#{major}.0.0"
      [major, minor] -> "#{major}.#{minor}.0"
      _ -> version
    end
  end

  def create_package_release(%{
        package:
          %Package{id: package_id, scope: scope, name: name, repository_full_handle: repository_full_handle} = package,
        version: version,
        token: token
      }) do
    {:ok, source_archive_directory} = Briefly.create(type: :directory)

    source_result =
      if has_submodules?(%{repository_full_handle: repository_full_handle, token: token, tag: version}) do
        Logger.info("Using git clone with submodules for #{repository_full_handle}@#{version}")
        repo_name = repository_full_handle |> String.split("/") |> List.last()
        clone_dest = Path.join(source_archive_directory, "#{repo_name}-#{String.replace(version, "/", "-")}")

        clone_with_submodules(%{
          repository_full_handle: repository_full_handle,
          tag: version,
          token: token,
          destination: clone_dest
        })
      else
        get_source_from_zipball(%{
          repository_full_handle: repository_full_handle,
          tag: version,
          token: token,
          temp_dir: source_archive_directory
        })
      end

    case source_result do
      {:error, reason} ->
        {:error, reason}

      {:ok, source_directory} ->
        create_package_release_from_source(%{
          package: package,
          package_id: package_id,
          scope: scope,
          name: name,
          version: version,
          token: token,
          source_archive_directory: source_archive_directory,
          source_directory: source_directory
        })
    end
  end

  defp create_package_release_from_source(%{
         package: package,
         package_id: package_id,
         scope: scope,
         name: name,
         version: version,
         token: token,
         source_archive_directory: source_archive_directory,
         source_directory: source_directory
       }) do
    new_source_archive_path = "#{source_archive_directory}/source_archive.zip"

    {_, 0} =
      System.cmd(
        "zip",
        [
          "--symlinks",
          "-r",
          new_source_archive_path,
          Path.basename(source_directory)
        ],
        cd: source_archive_directory
      )

    data = File.read!(new_source_archive_path)

    object_key =
      package_object_key(%{scope: scope, name: name},
        version: version,
        path: "source_archive.zip"
      )

    Storage.put_object(object_key, data, :registry)

    checksum =
      :sha256
      |> Crypto.hash_init()
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

  defp has_submodules?(%{repository_full_handle: repository_full_handle, token: token, tag: tag}) do
    case VCS.get_repository_content(
           %{repository_full_handle: repository_full_handle, provider: :github, token: token},
           reference: tag,
           path: ".gitmodules"
         ) do
      {:ok, %Content{content: content}} when is_binary(content) and content != "" -> true
      _ -> false
    end
  end

  defp clone_with_submodules(%{
         repository_full_handle: repository_full_handle,
         tag: tag,
         token: token,
         destination: destination
       }) do
    clone_url = "https://#{token}@github.com/#{repository_full_handle}.git"

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
             "--recurse-submodules",
             "--shallow-submodules",
             clone_url,
             destination
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        remove_git_metadata(destination)
        {:ok, destination}

      {output, code} ->
        Logger.warning("Git clone failed for #{repository_full_handle}@#{tag} (exit #{code}): #{output}")
        {:error, "Git clone failed (exit #{code}): #{output}"}
    end
  end

  defp remove_git_metadata(directory) do
    directory
    |> Path.join("**/.git")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(&File.rm_rf!/1)

    gitmodules_path = Path.join(directory, ".gitmodules")
    if File.exists?(gitmodules_path), do: File.rm(gitmodules_path)
  end

  defp get_source_from_zipball(%{
         repository_full_handle: repository_full_handle,
         tag: tag,
         token: token,
         temp_dir: temp_dir
       }) do
    {:ok, source_archive_path} =
      VCS.get_source_archive_by_tag_and_repository_full_handle(%{
        provider: :github,
        repository_full_handle: repository_full_handle,
        tag: tag,
        token: token
      })

    System.cmd("unzip", [source_archive_path, "-d", temp_dir])

    [source_directory] = File.ls!(temp_dir)
    {:ok, Path.join(temp_dir, source_directory)}
  end

  defp create_package_manifests(%{
         package: %Package{repository_full_handle: repository_full_handle} = package,
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

    Enum.each(root_contents, fn %Content{path: path} ->
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
         package: %Package{scope: scope, name: name, repository_full_handle: repository_full_handle},
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
      package_manifest_content,
      :registry
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

  def get_package_release_by_version(%{package: %Package{id: package_id}, version: version}, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    PackageRelease
    |> Repo.get_by(package_id: package_id, version: version)
    |> Repo.preload(preload)
  end

  def package_manifest_as_string(%{scope: scope, name: name, version: version}) do
    object_key =
      package_object_key(%{scope: scope, name: name}, version: version, path: "Package.swift")

    if Storage.object_exists?(object_key, :registry) do
      package_manifest =
        Storage.get_object_as_string(object_key, :registry)

      {:ok, package_manifest}
    else
      {:error, :not_found}
    end
  end

  def package_object_key(%{scope: scope, name: name}, opts \\ []) do
    version = Keyword.get(opts, :version, nil)
    path = Keyword.get(opts, :path, nil)
    object_key = String.downcase("registry/swift/#{scope}/#{name}")

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
