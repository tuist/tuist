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

    Package
    |> Repo.get_by(scope: scope, name: name)
    |> Repo.preload(preload)
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
    %{
      repository_full_handle: repository_full_handle,
      provider: :github,
      token: token
    }
    |> VCS.get_tags()
    |> Enum.map(& &1.name)
    |> Enum.filter(fn version ->
      # Matches semantic version as per: https://semver.org/
      # Examples: 1.0.0, 1.0.0-alpha, 1.0.0-alpha.1, 1.1
      # Skip dev versions like 0.9.3-dev1985
      Regex.match?(~r/^v?\d+\.\d+(\.\d+)?[0-9A-Za-z-]*(\.[0-9A-Za-z]*)?$/, version) and
        not Regex.match?(~r/-dev/, version) and
        not Enum.any?(package.package_releases, &(&1.version == semantic_version(version)))
    end)
    |> Enum.uniq_by(&semantic_version(&1))
    |> Enum.map(fn version ->
      %{scope: scope, name: name, version: version}
    end)
  end

  defp semantic_version(version) do
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
    {:ok, source_archive_path} =
      VCS.get_source_archive_by_tag_and_repository_full_handle(%{
        provider: :github,
        repository_full_handle: repository_full_handle,
        tag: version,
        token: token
      })

    {:ok, source_archive_directory} = Briefly.create(type: :directory)

    System.cmd(
      "unzip",
      [source_archive_path, "-d", source_archive_directory]
    )

    [source_directory] = File.ls!(source_archive_directory)

    new_source_archive_directory = "#{source_archive_directory}/source_archive.zip"

    (source_archive_directory <> "/" <> source_directory)
    |> File.ls!()
    |> Enum.each(fn file_name ->
      file_path = source_archive_directory <> "/" <> source_directory <> "/" <> file_name

      if (String.ends_with?(file_name, "Package.swift") or
            Regex.match?(
              @alternate_package_manifest_regex,
              file_name
            )) and not File.dir?(file_path) do
        file_content =
          File.read!(file_path)

        File.write!(
          file_path,
          replace_package_by_name_references_with_product_in_package_manifest(file_content)
        )
      end
    end)

    {_, 0} =
      System.cmd(
        "zip",
        [
          "--symlinks",
          "-r",
          new_source_archive_directory,
          source_directory
        ],
        cd: source_archive_directory
      )

    data = File.read!(new_source_archive_directory)

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
      replace_package_by_name_references_with_product_in_package_manifest(package_manifest_content),
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

  defp replace_package_by_name_references_with_product_in_package_manifest(package_manifest) do
    packages =
      extract_url_only_packages(package_manifest) ++ extract_named_url_packages(package_manifest)

    Enum.reduce(packages, package_manifest, fn package, package_manifest ->
      package
      |> replace_targets_content(package_manifest)
      |> String.replace(
        ~r/(?<!.product\(name: )"#{package.by_name_reference}"/is,
        "\"#{package.name}\""
      )
      # Workaround for a bug in SwiftPM fixed in: https://github.com/swiftlang/swift-package-manager/pull/8194
      |> String.replace(
        ~r/package:\s*"#{package.name}"/is,
        "package: \"#{package.name}\""
      )
    end)
  end

  # This method replaces content only inside the targets: [..] array.
  defp replace_targets_content(package, package_manifest) do
    Enum.reduce(
      Regex.scan(~r/targets:\s*\[/, package_manifest, return: :index),
      package_manifest,
      fn [{bracket_position, length}], package_manifest ->
        case find_matching_bracket(package_manifest, bracket_position + length, 1) do
          {:ok, position} ->
            {pre_content, content} = String.split_at(package_manifest, bracket_position)

            {content_to_replace, post_content} = String.split_at(content, position - bracket_position + 1)

            replaced_content =
              content_to_replace
              |> String.replace(
                ~r/(?<!.product\(name: )"#{package.by_name_reference}"/is,
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

            pre_content <> replaced_content <> post_content

          {:error, _} ->
            package_manifest
        end
      end
    )
  end

  defp find_matching_bracket(string, pos, _count) when pos >= byte_size(string) do
    {:error, "No matching bracket found"}
  end

  defp find_matching_bracket(string, pos, count) do
    case String.at(string, pos) do
      "[" ->
        find_matching_bracket(string, pos + 1, count + 1)

      "]" ->
        if count == 1 do
          {:ok, pos}
        else
          find_matching_bracket(string, pos + 1, count - 1)
        end

      _ ->
        find_matching_bracket(string, pos + 1, count)
    end
  end

  defp extract_url_only_packages(package_manifest) do
    ~r/\.package\(\s*url:\s*"([^"\\]+)"/
    |> Regex.scan(package_manifest)
    |> Enum.map(&List.last/1)
    |> Enum.filter(&valid_repository_url?/1)
    |> Enum.map(&VCS.get_repository_full_handle_from_url/1)
    |> Enum.map(&elem(&1, 1))
    |> Enum.map(&get_package_scope_and_name_from_repository_full_handle/1)
    |> Enum.map(&%{scope: &1.scope, name: &1.name, by_name_reference: &1.name})
  end

  defp extract_named_url_packages(package_manifest) do
    ~r/\.package\(\s*name:\s*"([^"\\]+)"\s*,\s*url:\s*"([^"\\]+)/
    |> Regex.scan(package_manifest)
    |> Enum.map(&Enum.slice(&1, -2, 2))
    |> Enum.filter(&valid_repository_url?(List.last(&1)))
    |> Enum.map(fn [by_name_reference, package_url] ->
      [scope, package_name] =
        package_url
        |> VCS.get_repository_full_handle_from_url()
        |> elem(1)
        |> String.split("/")

      %{scope: scope, name: package_name, by_name_reference: by_name_reference}
    end)
  end

  defp valid_repository_url?(package_url) do
    case VCS.get_repository_full_handle_from_url(package_url) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def package_manifest_as_string(%{scope: scope, name: name, version: version}) do
    object_key =
      package_object_key(%{scope: scope, name: name}, version: version, path: "Package.swift")

    if Storage.object_exists?(object_key, :registry) do
      package_manifest =
        Storage.get_object_as_string(object_key, :registry)

      packages =
        ~r/url:\s*"([^"]+)"/
        |> Regex.scan(package_manifest)
        |> Enum.map(&List.last/1)
        |> Enum.filter(&valid_repository_url?/1)
        |> Enum.map(&VCS.get_repository_full_handle_from_url/1)
        |> Enum.map(&elem(&1, 1))
        |> Enum.map(&get_package_scope_and_name_from_repository_full_handle/1)

      package_manifest =
        Enum.reduce(packages, package_manifest, fn package, package_manifest ->
          String.replace(
            package_manifest,
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
