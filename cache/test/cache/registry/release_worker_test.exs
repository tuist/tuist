defmodule Cache.Registry.ReleaseWorkerTest do
  use CacheWeb.ConnCase, async: false
  use Mimic

  alias Cache.Registry.Lock
  alias Cache.Registry.Metadata
  alias Cache.Registry.ReleaseWorker
  alias ExAws.Operation.S3
  alias ExAws.S3.Upload

  setup :set_mimic_from_context

  setup do
    Application.put_env(:cache, :registry_github_token, "token")
    on_exit(fn -> Application.delete_env(:cache, :registry_github_token) end)
    stub(Lock, :release, fn _ -> :ok end)
    :ok
  end

  test "skips when release already exists" do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ -> {:ok, :acquired} end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", _opts ->
      {:ok, %{"releases" => %{"1.0.0" => %{"checksum" => "abc", "manifests" => []}}}}
    end)

    stub(TuistCommon.GitHub, :download_zipball, fn _, _, _, _, _ -> flunk("unexpected zipball download") end)
    stub(TuistCommon.GitHub, :list_repository_contents, fn _, _, _, _ -> flunk("unexpected contents request") end)
    stub(TuistCommon.GitHub, :get_file_content, fn _, _, _, _, _ -> flunk("unexpected file request") end)

    assert :ok =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end

  test "skips when lock is already held" do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:error, :already_locked}
    end)

    stub(Metadata, :get_package, fn _, _, _ -> flunk("should not check metadata") end)

    assert :ok =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end

  test "downloads, uploads, and updates metadata for new release" do
    manifest_content = "// swift-tools-version:5.9\nimport PackageDescription"

    # Release lock acquired
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
    end)

    # No existing metadata — new package
    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    # No submodules
    expect(TuistCommon.GitHub, :get_file_content, fn "apple/swift-argument-parser",
                                                     "token",
                                                     ".gitmodules",
                                                     "v1.0.0",
                                                     _ ->
      {:error, :not_found}
    end)

    # Download zipball — write a real file so checksum works
    expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser",
                                                     "token",
                                                     "v1.0.0",
                                                     archive_path,
                                                     _ ->
      File.write!(archive_path, "fake-zip-content")
      :ok
    end)

    # Upload source archive via streaming upload
    expect(Upload, :stream_file, fn path ->
      assert File.exists?(path)
      ["fake-zip-content"]
    end)

    expect(ExAws.S3, :upload, fn _stream, _bucket, key, _opts ->
      assert key == "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
      %S3{http_method: :put, bucket: "test", path: key}
    end)

    # First ExAws.request call — source archive upload
    # Second ExAws.request call — manifest upload
    # Third ExAws.request call — (none, put_package is mocked)
    expect(ExAws, :request, 2, fn _op ->
      {:ok, %{status_code: 200, body: ""}}
    end)

    # List repo contents — return Package.swift
    expect(TuistCommon.GitHub, :list_repository_contents, fn "apple/swift-argument-parser", "token", "v1.0.0", _ ->
      {:ok, [%{"path" => "Package.swift", "type" => "file"}]}
    end)

    # Fetch the manifest content
    expect(TuistCommon.GitHub, :get_file_content, fn "apple/swift-argument-parser",
                                                     "token",
                                                     "Package.swift",
                                                     "v1.0.0",
                                                     _ ->
      {:ok, manifest_content}
    end)

    # Metadata lock for update
    expect(Lock, :try_acquire, fn {:package, "apple", "swift-argument-parser"}, _ ->
      {:ok, :acquired}
    end)

    # Fresh metadata check during update — still doesn't exist
    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    # Metadata write
    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", metadata ->
      assert metadata["scope"] == "apple"
      assert metadata["name"] == "swift-argument-parser"
      assert metadata["repository_full_handle"] == "apple/swift-argument-parser"

      release = metadata["releases"]["1.0.0"]
      assert is_binary(release["checksum"])
      assert [%{"swift_version" => nil, "swift_tools_version" => "5.9"}] = release["manifests"]
      :ok
    end)

    assert :ok =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end

  test "downloads, uploads, and updates metadata with alternate manifests" do
    default_manifest = "// swift-tools-version:5.7\nimport PackageDescription"
    alternate_manifest = "// swift-tools-version:5.9\nimport PackageDescription"

    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser",
                                                     "token",
                                                     "v1.0.0",
                                                     archive_path,
                                                     _ ->
      File.write!(archive_path, "fake-zip-content")
      :ok
    end)

    expect(Upload, :stream_file, fn _path -> ["fake-zip-content"] end)

    expect(ExAws.S3, :upload, fn _stream, _bucket, _key, _opts ->
      %S3{http_method: :put, bucket: "test", path: "key"}
    end)

    # 3 ExAws.request calls: source archive upload + 2 manifest uploads
    expect(ExAws, :request, 3, fn _op -> {:ok, %{status_code: 200, body: ""}} end)

    expect(TuistCommon.GitHub, :list_repository_contents, fn "apple/swift-argument-parser", "token", "v1.0.0", _ ->
      {:ok,
       [
         %{"path" => "Package.swift", "type" => "file"},
         %{"path" => "Package@swift-5.9.swift", "type" => "file"},
         %{"path" => "README.md", "type" => "file"}
       ]}
    end)

    # Three get_file_content calls: .gitmodules check + 2 manifest fetches
    expect(TuistCommon.GitHub, :get_file_content, 3, fn
      "apple/swift-argument-parser", "token", ".gitmodules", "v1.0.0", _ ->
        {:error, :not_found}

      "apple/swift-argument-parser", "token", "Package.swift", "v1.0.0", _ ->
        {:ok, default_manifest}

      "apple/swift-argument-parser", "token", "Package@swift-5.9.swift", "v1.0.0", _ ->
        {:ok, alternate_manifest}
    end)

    expect(Lock, :try_acquire, fn {:package, "apple", "swift-argument-parser"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", metadata ->
      release = metadata["releases"]["1.0.0"]
      manifests = release["manifests"]
      assert length(manifests) == 2

      default = Enum.find(manifests, &is_nil(&1["swift_version"]))
      assert default["swift_tools_version"] == "5.7"

      alternate = Enum.find(manifests, &(&1["swift_version"] == "5.9"))
      assert alternate["swift_tools_version"] == "5.9"
      :ok
    end)

    assert :ok =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end
end
