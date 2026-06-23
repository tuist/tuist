defmodule Tuist.Registry.Swift.ReleaseWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Ecto.Adapters.SQL.Sandbox
  alias ExAws.Operation.S3
  alias ExAws.S3.Upload
  alias Tuist.Registry
  alias Tuist.Registry.Swift.Lock
  alias Tuist.Registry.Swift.Metadata
  alias Tuist.Registry.Swift.ReleaseWorker

  @default_manifest_content "// swift-tools-version:5.9\nimport PackageDescription"

  setup :set_mimic_from_context

  setup do
    Sandbox.checkout(Tuist.Repo)
    stub(Registry, :swift_registry_github_token, fn -> "token" end)
    stub(Registry, :registry_bucket, fn -> "test-bucket" end)
    stub(Lock, :release, fn _ -> :ok end)

    :ok
  end

  test "skips when release already exists" do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
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

  test "downloads, uploads, and updates metadata for a new release" do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(TuistCommon.GitHub, :list_repository_contents, fn "apple/swift-argument-parser", "token", "v1.0.0", _ ->
      {:ok, [%{"path" => "Package.swift", "type" => "file"}]}
    end)

    expect(TuistCommon.GitHub, :get_file_content, 2, fn
      "apple/swift-argument-parser", "token", "Package.swift", "v1.0.0", _ ->
        {:ok, @default_manifest_content}

      "apple/swift-argument-parser", "token", ".gitmodules", "v1.0.0", _ ->
        {:error, :not_found}
    end)

    expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser", "token", "v1.0.0", archive_path, _ ->
      write_basic_zipball(archive_path)
      :ok
    end)

    expect(Upload, :stream_file, fn path ->
      assert File.exists?(path)
      [File.read!(path)]
    end)

    expect(ExAws.S3, :upload, fn _stream, "test-bucket", key, _opts ->
      assert key == "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
      %S3{http_method: :put, bucket: "test-bucket", path: key}
    end)

    expect(ExAws, :request, 2, fn _op ->
      {:ok, %{status_code: 200, body: ""}}
    end)

    expect(Lock, :try_acquire, fn {:package, "apple", "swift-argument-parser"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

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

  test "deduplicates manifest metadata by Swift tools version" do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(TuistCommon.GitHub, :list_repository_contents, fn "apple/swift-argument-parser", "token", "v1.0.0", _ ->
      {:ok,
       [
         %{"path" => "Package.swift", "type" => "file"},
         %{"path" => "Package@swift-5.9.swift", "type" => "file"},
         %{"path" => "Package@swift-5.10.swift", "type" => "file"}
       ]}
    end)

    expect(TuistCommon.GitHub, :get_file_content, 4, fn
      "apple/swift-argument-parser", "token", "Package.swift", "v1.0.0", _ ->
        {:ok, @default_manifest_content}

      "apple/swift-argument-parser", "token", "Package@swift-5.9.swift", "v1.0.0", _ ->
        {:ok, @default_manifest_content}

      "apple/swift-argument-parser", "token", "Package@swift-5.10.swift", "v1.0.0", _ ->
        {:ok, "// swift-tools-version:5.10\nimport PackageDescription"}

      "apple/swift-argument-parser", "token", ".gitmodules", "v1.0.0", _ ->
        {:error, :not_found}
    end)

    expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser", "token", "v1.0.0", archive_path, _ ->
      write_basic_zipball(archive_path)
      :ok
    end)

    expect(Upload, :stream_file, fn path ->
      assert File.exists?(path)
      [File.read!(path)]
    end)

    expect(ExAws.S3, :upload, fn _stream, "test-bucket", key, _opts ->
      assert key == "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
      %S3{http_method: :put, bucket: "test-bucket", path: key}
    end)

    expect(ExAws, :request, 4, fn _op ->
      {:ok, %{status_code: 200, body: ""}}
    end)

    expect(Lock, :try_acquire, fn {:package, "apple", "swift-argument-parser"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", metadata ->
      manifests = metadata["releases"]["1.0.0"]["manifests"]

      assert manifests == [
               %{"swift_version" => nil, "swift_tools_version" => "5.9"},
               %{"swift_version" => "5.10", "swift_tools_version" => "5.10"}
             ]

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

  defp write_basic_zipball(archive_path) do
    tmp = Path.join(Path.dirname(archive_path), "zipball_content")
    top_dir = Path.join(tmp, "repo-v1.0.0")

    File.mkdir_p!(top_dir)
    File.write!(Path.join(top_dir, "Package.swift"), @default_manifest_content)
    {_, 0} = System.cmd("zip", ["-r", archive_path, "repo-v1.0.0"], cd: tmp)
    File.rm_rf!(tmp)
  end
end
