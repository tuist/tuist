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
    stub(Registry, :registry_s3_config, fn -> [host: "registry.example.com"] end)
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

  test "repairs a release that was skipped before skip classifications were versioned" do
    legacy_metadata = %{
      "releases" => %{},
      "skipped_releases" => %{"1.0.0" => %{"reason" => "missing_manifests"}}
    }

    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:ok, legacy_metadata}
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

    stub_archive_upload(3)

    expect(Lock, :try_acquire, fn {:package, "apple", "swift-argument-parser"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:ok, legacy_metadata}
    end)

    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", metadata ->
      assert metadata["scope"] == "apple"
      assert metadata["name"] == "swift-argument-parser"
      assert metadata["repository_full_handle"] == "apple/swift-argument-parser"

      release = metadata["releases"]["1.0.0"]
      assert is_binary(release["checksum"])
      assert [%{"swift_version" => nil, "swift_tools_version" => "5.9"}] = release["manifests"]
      refute Map.has_key?(metadata["skipped_releases"], "1.0.0")
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

  test "snoozes instead of erroring when the package lock stays contended past the retry budget" do
    stub(Lock, :try_acquire, fn
      {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
        {:ok, :acquired}

      {:package, "apple", "swift-argument-parser"}, _ ->
        {:error, :already_locked}
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

    stub_archive_upload(3)

    stub(Metadata, :put_package, fn _, _, _ -> flunk("unexpected metadata write while the lock is contended") end)

    assert {:snooze, 30} =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end

  test "records a skipped release when the tag has no root manifest" do
    stub(Lock, :try_acquire, fn
      {:release, "apple", "swift-argument-parser", "1.0.0"}, _ -> {:ok, :acquired}
      {:package, "apple", "swift-argument-parser"}, _ -> {:ok, :acquired}
    end)

    stub(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(TuistCommon.GitHub, :list_repository_contents, fn "apple/swift-argument-parser", "token", "v1.0.0", _ ->
      {:ok, [%{"path" => "README.md", "type" => "file"}]}
    end)

    stub(TuistCommon.GitHub, :download_zipball, fn _, _, _, _, _ -> flunk("unexpected zipball download") end)
    stub(TuistCommon.GitHub, :get_file_content, fn _, _, _, _, _ -> flunk("unexpected file request") end)

    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", metadata ->
      assert metadata["skipped_releases"]["1.0.0"] == %{
               "classification_version" => 2,
               "reason" => "missing_manifests"
             }

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

  test "discards the job when GitHub rate limits a manifest request" do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(TuistCommon.GitHub, :list_repository_contents, fn "apple/swift-argument-parser", "token", "v1.0.0", _ ->
      {:ok, [%{"path" => "Package.swift", "type" => "file"}]}
    end)

    expect(TuistCommon.GitHub, :get_file_content, fn
      "apple/swift-argument-parser", "token", "Package.swift", "v1.0.0", _ ->
        {:error, {:rate_limited, 403}}
    end)

    stub(TuistCommon.GitHub, :download_zipball, fn _, _, _, _, _ -> flunk("unexpected zipball download") end)

    stub(Metadata, :put_package, fn _, _, _ -> flunk("unexpected skipped-release write") end)

    assert {:discard,
            {:manifest_fetch_failed,
             [
               %{
                 path: "Package.swift",
                 reason: {:rate_limited, 403}
               }
             ]}} =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end

  test "snoozes immediately without retrying when the skip-write lock is contended" do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
    end)

    stub(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(TuistCommon.GitHub, :list_repository_contents, fn "apple/swift-argument-parser", "token", "v1.0.0", _ ->
      {:ok, [%{"path" => "README.md", "type" => "file"}]}
    end)

    stub(TuistCommon.GitHub, :download_zipball, fn _, _, _, _, _ -> flunk("unexpected zipball download") end)
    stub(TuistCommon.GitHub, :get_file_content, fn _, _, _, _, _ -> flunk("unexpected file request") end)

    # A single package-lock acquisition attempt (no in-job retry): a second call
    # would raise, since only this one is expected.
    expect(Lock, :try_acquire, fn {:package, "apple", "swift-argument-parser"}, _ ->
      {:error, :already_locked}
    end)

    stub(Metadata, :put_package, fn _, _, _ -> flunk("unexpected metadata write while the lock is contended") end)

    assert {:snooze, 30} =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end

  test "retries the contended package lock in-job and records the release without erroring" do
    {:ok, package_lock_attempts} = Agent.start_link(fn -> 0 end)

    stub(Lock, :try_acquire, fn
      {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
        {:ok, :acquired}

      {:package, "apple", "swift-argument-parser"}, _ ->
        attempt = Agent.get_and_update(package_lock_attempts, &{&1, &1 + 1})
        if attempt < 2, do: {:error, :already_locked}, else: {:ok, :acquired}
    end)

    stub(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
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

    stub_archive_upload(3)

    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", metadata ->
      assert is_binary(metadata["releases"]["1.0.0"]["checksum"])
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

    assert Agent.get(package_lock_attempts, & &1) == 3
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

    stub_archive_upload(5)

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

  test "treats a GitHub private repository permission error as a skippable submodule failure" do
    output = """
    remote: Write access to repository not granted.
    fatal: unable to access 'https://github.com/tuist/TuistCacheEE/': The requested URL returned error: 403
    """

    assert ReleaseWorker.skippable_submodule_failure?(output)
  end

  describe "zip_directory/2" do
    test "preserves symlinks inside code-signed bundles while flattening other symlinks" do
      tmp = Path.join(System.tmp_dir!(), "zip_directory_test_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(tmp) end)

      source = Path.join(tmp, "repo-v1.0.0")
      framework = Path.join([source, "Vendor", "Adyen3DS2.xcframework", "ios-maccatalyst", "Adyen3DS2.framework"])
      version_a = Path.join([framework, "Versions", "A"])
      File.mkdir_p!(Path.join(version_a, "Resources"))

      File.write!(Path.join(source, "README.md"), "readme")
      # Non-bundle symlink: should be flattened into a regular file.
      File.ln_s!("README.md", Path.join(source, "CLAUDE.md"))

      File.write!(Path.join(version_a, "Adyen3DS2"), "binary")
      File.write!(Path.join([version_a, "Resources", "Info.plist"]), "plist")
      # Sealed bundle symlinks: must survive as symlinks.
      File.ln_s!("A", Path.join([framework, "Versions", "Current"]))
      File.ln_s!("Versions/Current/Adyen3DS2", Path.join(framework, "Adyen3DS2"))
      File.ln_s!("Versions/Current/Resources", Path.join(framework, "Resources"))

      archive_path = Path.join(tmp, "source_archive.zip")
      assert :ok = ReleaseWorker.zip_directory(source, archive_path)

      extract_dir = Path.join(tmp, "extract")
      File.mkdir_p!(extract_dir)
      {_, 0} = System.cmd("unzip", ["-q", archive_path, "-d", extract_dir])

      extracted_framework =
        Path.join([
          extract_dir,
          "repo-v1.0.0",
          "Vendor",
          "Adyen3DS2.xcframework",
          "ios-maccatalyst",
          "Adyen3DS2.framework"
        ])

      assert {:ok, %File.Stat{type: :regular}} = File.lstat(Path.join([extract_dir, "repo-v1.0.0", "CLAUDE.md"]))
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join([extracted_framework, "Versions", "Current"]))
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(extracted_framework, "Adyen3DS2"))
      assert {:ok, %File.Stat{type: :symlink}} = File.lstat(Path.join(extracted_framework, "Resources"))
      assert {:ok, "A"} = File.read_link(Path.join([extracted_framework, "Versions", "Current"]))
    end

    test "flattens a root-level symlink even when it is named like a code-signed bundle" do
      tmp = Path.join(System.tmp_dir!(), "zip_directory_bundle_named_link_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(tmp) end)

      source = Path.join(tmp, "repo-v1.0.0")
      File.mkdir_p!(source)
      File.write!(Path.join(source, "README.md"), "readme")
      # A package-root symlink whose own basename matches a bundle extension must
      # still be flattened, since it is a root-level symlink SwiftPM mishandles.
      File.ln_s!("README.md", Path.join(source, "Widget.framework"))

      archive_path = Path.join(tmp, "source_archive.zip")
      assert :ok = ReleaseWorker.zip_directory(source, archive_path)

      extract_dir = Path.join(tmp, "extract")
      File.mkdir_p!(extract_dir)
      {_, 0} = System.cmd("unzip", ["-q", archive_path, "-d", extract_dir])

      assert {:ok, %File.Stat{type: :regular}} =
               File.lstat(Path.join([extract_dir, "repo-v1.0.0", "Widget.framework"]))
    end
  end

  test "refuses an archive whose directory entries would not be traversable after extraction" do
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
      write_unreadable_directory_zipball(archive_path)
      :ok
    end)

    reject(ExAws.S3, :upload, 4)
    reject(Metadata, :put_package, 3)

    assert {:error, {:archive_directories_not_traversable, 1, ["repo-v1.0.0/"]}} =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end

  test "refuses to republish a version whose bytes differ from the published checksum" do
    stub_successful_fetch()

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:ok, %{"releases" => %{"1.0.0" => %{"checksum" => "already-published", "manifests" => []}}}}
    end)

    reject(ExAws.S3, :upload, 4)
    reject(Metadata, :put_package, 3)

    assert {:discard, {:checksum_change_refused, %{published: "already-published", rebuilt: rebuilt}}} =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0",
                 "force" => true
               }
             })

    assert is_binary(rebuilt)
  end

  test "republishes a version with different bytes when the override is set" do
    stub_successful_fetch()

    stub(Metadata, :get_package, fn "apple", "swift-argument-parser", _opts ->
      {:ok, %{"releases" => %{"1.0.0" => %{"checksum" => "already-published", "manifests" => []}}}}
    end)

    expect(Lock, :try_acquire, fn {:package, "apple", "swift-argument-parser"}, _ -> {:ok, :acquired} end)
    stub_archive_upload(3)

    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", metadata ->
      refute metadata["releases"]["1.0.0"]["checksum"] == "already-published"
      :ok
    end)

    assert :ok =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0",
                 "force" => true,
                 "allow_checksum_change" => true
               }
             })
  end

  test "leaves the catalog alone when storage does not hold the archive that was uploaded" do
    stub_successful_fetch()

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(Upload, :stream_file, fn path -> [File.read!(path)] end)

    expect(ExAws.S3, :upload, fn _stream, "test-bucket", key, _opts ->
      %S3{http_method: :put, bucket: "test-bucket", path: key}
    end)

    # Storage still holds a different object than the one just uploaded, which
    # is what leaves a catalog entry advertising a checksum nothing can serve.
    expect(ExAws, :request, 2, fn
      %S3{http_method: :head}, _config ->
        {:ok, %{status_code: 200, headers: [{"x-amz-meta-sha256", "a-previously-stored-archive"}]}}

      _operation, _config ->
        {:ok, %{status_code: 200, body: ""}}
    end)

    reject(Metadata, :put_package, 3)

    assert {:error, {:stored_archive_mismatch, _key, %{stored: "a-previously-stored-archive"}}} =
             ReleaseWorker.perform(%Oban.Job{
               args: %{
                 "scope" => "apple",
                 "name" => "swift-argument-parser",
                 "repository_full_handle" => "apple/swift-argument-parser",
                 "tag" => "v1.0.0"
               }
             })
  end

  defp stub_successful_fetch do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
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
  end

  # Reproduces the shape the pre-2025 writer produced: entries written by
  # Erlang's :zip carry a bare 0644 mode with no directory type bits, so the
  # extracted package root has no execute bit and cannot be descended into.
  defp write_unreadable_directory_zipball(archive_path) do
    {:ok, _path} =
      :zip.create(String.to_charlist(archive_path), [
        {~c"repo-v1.0.0/", <<>>},
        {~c"repo-v1.0.0/Package.swift", @default_manifest_content}
      ])

    :ok
  end

  # The release worker reads the stored object's digest back before it touches
  # the catalog, so the upload and the HEAD share one agent rather than a fixed
  # value the test would have to know in advance.
  defp stub_archive_upload(request_count) do
    {:ok, uploaded_digest} = Agent.start_link(fn -> nil end)

    expect(Upload, :stream_file, fn path ->
      assert File.exists?(path)
      Agent.update(uploaded_digest, fn _previous -> sha256(path) end)
      [File.read!(path)]
    end)

    expect(ExAws.S3, :upload, fn _stream, "test-bucket", key, _opts ->
      assert key == "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
      %S3{http_method: :put, bucket: "test-bucket", path: key}
    end)

    expect(ExAws, :request, request_count, fn
      %S3{http_method: :head}, config ->
        assert config == [host: "registry.example.com"]
        {:ok, %{status_code: 200, headers: [{"x-amz-meta-sha256", Agent.get(uploaded_digest, & &1)}]}}

      _operation, config ->
        assert config == [host: "registry.example.com"]
        {:ok, %{status_code: 200, body: ""}}
    end)
  end

  defp sha256(path) do
    path
    |> File.stream!(2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
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
