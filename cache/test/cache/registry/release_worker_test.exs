defmodule Cache.Registry.ReleaseWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Cache.Repo
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.Config
  alias Cache.Registry.Lock
  alias Cache.Registry.Metadata
  alias Cache.Registry.ReleaseWorker
  alias Ecto.Adapters.SQL.Sandbox
  alias ExAws.Operation.S3
  alias ExAws.S3.Upload

  @default_manifest_content "// swift-tools-version:5.9\nimport PackageDescription"

  setup :set_mimic_from_context

  setup do
    Sandbox.checkout(Cache.Repo)
    stub(Config, :registry_github_token, fn -> "token" end)
    stub(Config, :registry_bucket, fn -> "test-bucket" end)
    stub(Config, :registry_enabled?, fn -> true end)
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
      write_basic_zipball(archive_path)
      :ok
    end)

    # Upload source archive via streaming upload
    expect(Upload, :stream_file, fn path ->
      assert File.exists?(path)
      [File.read!(path)]
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
      {:ok, @default_manifest_content}
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
    alternate_manifest = @default_manifest_content

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
      write_basic_zipball(archive_path)
      :ok
    end)

    expect(Upload, :stream_file, fn path ->
      assert File.exists?(path)
      [File.read!(path)]
    end)

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

  describe "symlink resolution" do
    test "zip_directory resolves RevenueCat-style directory symlinks and removes recursive ones" do
      root = Briefly.create!(directory: true)
      source_dir = Path.join(root, "repo")
      archive_path = Path.join(root, "source_archive.zip")

      fixture_dir = Path.join([__DIR__, "../../fixtures/revenuecat_purchases_ios_spm_minimal"])
      {_, 0} = System.cmd("cp", ["-R", fixture_dir, source_dir])

      assert :ok = ReleaseWorker.zip_directory(source_dir, archive_path)

      {output, 0} = System.cmd("unzip", ["-Z", archive_path])
      lines = String.split(output, "\n")
      symlink_lines = Enum.filter(lines, &String.starts_with?(&1, "l"))

      assert symlink_lines == []

      dir_lines = Enum.filter(lines, &String.starts_with?(&1, "d"))
      assert Enum.any?(dir_lines, &String.contains?(&1, "CustomEntitlementComputation"))
      assert Enum.any?(dir_lines, &String.contains?(&1, "LocalReceiptParsing"))

      refute Enum.any?(lines, &String.contains?(&1, "purchases-root"))
    end

    test "zip_directory resolves symlinks for clone+zip path" do
      root = Briefly.create!(directory: true)
      source_dir = Path.join(root, "repo")
      archive_path = Path.join(root, "source_archive.zip")

      File.mkdir_p!(source_dir)
      File.write!(Path.join(source_dir, "target.md"), "content")
      File.ln_s!("target.md", Path.join(source_dir, "link.md"))

      assert :ok = ReleaseWorker.zip_directory(source_dir, archive_path)

      {output, 0} = System.cmd("unzip", ["-Z", archive_path])
      refute Enum.any?(String.split(output, "\n"), &String.starts_with?(&1, "l"))
    end

    test "zip_directory resolves directory symlinks whose target contains broken symlinks" do
      root = Briefly.create!(directory: true)
      source_dir = Path.join(root, "repo")
      archive_path = Path.join(root, "source_archive.zip")

      # On ext4 with htree, "BuildScripts" hashes before "Tests" in readdir order,
      # so `find -type l` discovers the BuildScripts directory symlink BEFORE the
      # broken symlink inside Tests/. This reproduces the production crash where
      # single-pass resolution called File.cp_r! with dereference_symlinks: true
      # on a directory containing a broken symlink (target doesn't exist), causing
      # a File.CopyError with :enoent.
      File.mkdir_p!(Path.join(source_dir, "Tests/nested"))
      File.write!(Path.join(source_dir, "Tests/nested/real_file.swift"), "")
      File.ln_s!("nonexistent_submodule_path", Path.join(source_dir, "Tests/nested/broken"))
      File.ln_s!("Tests", Path.join(source_dir, "BuildScripts"))

      assert :ok = ReleaseWorker.zip_directory(source_dir, archive_path)

      {output, 0} = System.cmd("unzip", ["-Z", archive_path])
      lines = String.split(output, "\n")
      symlink_lines = Enum.filter(lines, &String.starts_with?(&1, "l"))

      assert symlink_lines == []

      dir_lines = Enum.filter(lines, &String.starts_with?(&1, "d"))
      assert Enum.any?(dir_lines, &String.contains?(&1, "BuildScripts"))

      refute Enum.any?(lines, &String.contains?(&1, "broken"))
    end

    test "zip_directory removes symlinks that point outside root" do
      root = Briefly.create!(directory: true)
      source_dir = Path.join(root, "repo")
      outside_path = Path.join(root, "outside.txt")
      archive_path = Path.join(root, "source_archive.zip")

      File.mkdir_p!(source_dir)
      File.write!(outside_path, "secret")
      File.ln_s!("../outside.txt", Path.join(source_dir, "escaped.md"))

      assert :ok = ReleaseWorker.zip_directory(source_dir, archive_path)

      {output, 0} = System.cmd("unzip", ["-Z", archive_path])
      refute String.contains?(output, "escaped.md")
      refute String.contains?(output, "outside.txt")
    end

    test "resolves symlinks in downloaded zipball" do
      expect_release_sync_prerequisites()

      fixture_path = Path.join([__DIR__, "../../fixtures/with_symlinks.zip"])
      original_bytes = File.read!(fixture_path)

      expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser",
                                                       "token",
                                                       "v1.0.0",
                                                       archive_path,
                                                       _ ->
        File.cp!(fixture_path, archive_path)
        :ok
      end)

      expect(Upload, :stream_file, fn path ->
        {output, 0} = System.cmd("unzip", ["-Z", path])
        refute Enum.any?(String.split(output, "\n"), &String.starts_with?(&1, "l"))
        assert File.read!(path) != original_bytes
        [File.read!(path)]
      end)

      expect(ExAws.S3, :upload, fn _stream, _bucket, key, _opts ->
        assert key == "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
        %S3{http_method: :put, bucket: "test", path: key}
      end)

      expect(ExAws, :request, 2, fn _op ->
        {:ok, %{status_code: 200, body: ""}}
      end)

      expect_manifest_fetch(@default_manifest_content)
      expect_metadata_update_success()

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

    test "removes symlinks outside root from downloaded zipball" do
      expect_release_sync_prerequisites()

      expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser",
                                                       "token",
                                                       "v1.0.0",
                                                       archive_path,
                                                       _ ->
        tmp = Path.join(Path.dirname(archive_path), "zipball_content")
        top_dir = Path.join(tmp, "repo-v1.0.0")
        File.mkdir_p!(Path.join(top_dir, "Fixtures/symlinks"))
        File.write!(Path.join(top_dir, "Package.swift"), @default_manifest_content)
        File.ln_s!("/usr/bin/swift", Path.join(top_dir, "Fixtures/symlinks/swift"))
        {_, 0} = System.cmd("zip", ["--symlinks", "-r", archive_path, "repo-v1.0.0"], cd: tmp)
        File.rm_rf!(tmp)
        :ok
      end)

      expect(Upload, :stream_file, fn path ->
        {output, 0} = System.cmd("unzip", ["-Z", path])
        refute String.contains?(output, "Fixtures/symlinks/swift")
        refute Enum.any?(String.split(output, "\n"), &String.starts_with?(&1, "l"))
        [File.read!(path)]
      end)

      expect(ExAws.S3, :upload, fn _stream, _bucket, key, _opts ->
        assert key == "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
        %S3{http_method: :put, bucket: "test", path: key}
      end)

      expect(ExAws, :request, 2, fn _op ->
        {:ok, %{status_code: 200, body: ""}}
      end)

      expect_manifest_fetch(@default_manifest_content)
      expect_metadata_update_success()

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

    test "skips repack when archive has no symlinks" do
      expect_release_sync_prerequisites()

      fixture_path = Path.join([__DIR__, "../../fixtures/no_symlinks.zip"])
      original_bytes = File.read!(fixture_path)

      expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser",
                                                       "token",
                                                       "v1.0.0",
                                                       archive_path,
                                                       _ ->
        File.cp!(fixture_path, archive_path)
        :ok
      end)

      expect(Upload, :stream_file, fn path ->
        assert File.read!(path) == original_bytes
        [File.read!(path)]
      end)

      expect(ExAws.S3, :upload, fn _stream, _bucket, _key, _opts ->
        %S3{http_method: :put, bucket: "test", path: "key"}
      end)

      expect(ExAws, :request, 2, fn _op ->
        {:ok, %{status_code: 200, body: ""}}
      end)

      expect_manifest_fetch(@default_manifest_content)
      expect_metadata_update_success()

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

    test "resolves nested symlinks (symlink chain)" do
      expect_release_sync_prerequisites()

      expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser",
                                                       "token",
                                                       "v1.0.0",
                                                       archive_path,
                                                       _ ->
        tmp = Path.join(Path.dirname(archive_path), "zipball_content")
        top_dir = Path.join(tmp, "repo-v1.0.0")
        File.mkdir_p!(top_dir)
        File.write!(Path.join(top_dir, "a.md"), "# Content")
        File.ln_s!("a.md", Path.join(top_dir, "b.md"))
        File.ln_s!("b.md", Path.join(top_dir, "c.md"))
        File.write!(Path.join(top_dir, "Package.swift"), @default_manifest_content)
        {_, 0} = System.cmd("zip", ["--symlinks", "-r", archive_path, "repo-v1.0.0"], cd: tmp)
        File.rm_rf!(tmp)
        :ok
      end)

      expect(Upload, :stream_file, fn path ->
        {output, 0} = System.cmd("unzip", ["-Z", path])
        refute Enum.any?(String.split(output, "\n"), &String.starts_with?(&1, "l"))
        [File.read!(path)]
      end)

      expect(ExAws.S3, :upload, fn _stream, _bucket, key, _opts ->
        assert key == "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
        %S3{http_method: :put, bucket: "test", path: key}
      end)

      expect(ExAws, :request, 2, fn _op ->
        {:ok, %{status_code: 200, body: ""}}
      end)

      expect_manifest_fetch(@default_manifest_content)
      expect_metadata_update_success()

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

    test "handles broken symlinks gracefully" do
      expect_release_sync_prerequisites()

      expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser",
                                                       "token",
                                                       "v1.0.0",
                                                       archive_path,
                                                       _ ->
        tmp = Path.join(Path.dirname(archive_path), "zipball_content")
        top_dir = Path.join(tmp, "repo-v1.0.0")
        File.mkdir_p!(top_dir)
        File.write!(Path.join(top_dir, "Package.swift"), @default_manifest_content)
        File.ln_s!("nonexistent.md", Path.join(top_dir, "broken_link.md"))
        {_, 0} = System.cmd("zip", ["--symlinks", "-r", archive_path, "repo-v1.0.0"], cd: tmp)
        File.rm_rf!(tmp)
        :ok
      end)

      expect(Upload, :stream_file, fn path ->
        {output, 0} = System.cmd("unzip", ["-Z", path])
        refute Enum.any?(String.split(output, "\n"), &String.starts_with?(&1, "l"))
        [File.read!(path)]
      end)

      expect(ExAws.S3, :upload, fn _stream, _bucket, _key, _opts ->
        %S3{http_method: :put, bucket: "test", path: "key"}
      end)

      expect(ExAws, :request, 2, fn _op ->
        {:ok, %{status_code: 200, body: ""}}
      end)

      expect_manifest_fetch(@default_manifest_content)
      expect_metadata_update_success()

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

    test "fails closed when downloaded archive is not a valid zip" do
      expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
        {:ok, :acquired}
      end)

      expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
        {:error, :not_found}
      end)

      expect(TuistCommon.GitHub, :get_file_content, fn "apple/swift-argument-parser",
                                                       "token",
                                                       ".gitmodules",
                                                       "v1.0.0",
                                                       _ ->
        {:error, :not_found}
      end)

      expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser",
                                                       "token",
                                                       "v1.0.0",
                                                       archive_path,
                                                       _ ->
        File.write!(archive_path, "not-a-zip")
        :ok
      end)

      capture_log(fn ->
        assert {:error, {:invalid_archive, _status, _output}} =
                 ReleaseWorker.perform(%Oban.Job{
                   args: %{
                     "scope" => "apple",
                     "name" => "swift-argument-parser",
                     "repository_full_handle" => "apple/swift-argument-parser",
                     "tag" => "v1.0.0"
                   }
                 })
      end)
    end

    test "returns tagged error for archive with multiple top-level entries" do
      manifest_content = "// swift-tools-version:5.9\nimport PackageDescription"

      expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
        {:ok, :acquired}
      end)

      expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
        {:error, :not_found}
      end)

      expect(TuistCommon.GitHub, :get_file_content, fn "apple/swift-argument-parser",
                                                       "token",
                                                       ".gitmodules",
                                                       "v1.0.0",
                                                       _ ->
        {:error, :not_found}
      end)

      expect(TuistCommon.GitHub, :download_zipball, fn "apple/swift-argument-parser",
                                                       "token",
                                                       "v1.0.0",
                                                       archive_path,
                                                       _ ->
        tmp = Path.join(Path.dirname(archive_path), "zipball_content")
        first_dir = Path.join(tmp, "repo-v1.0.0")
        second_dir = Path.join(tmp, "repo-v1.0.1")
        File.mkdir_p!(first_dir)
        File.mkdir_p!(second_dir)
        File.write!(Path.join(first_dir, "Package.swift"), manifest_content)
        File.write!(Path.join(first_dir, "target.md"), "content")
        File.ln_s!("target.md", Path.join(first_dir, "link.md"))
        File.write!(Path.join(second_dir, "Package.swift"), manifest_content)
        {_, 0} = System.cmd("zip", ["--symlinks", "-r", archive_path, "repo-v1.0.0", "repo-v1.0.1"], cd: tmp)
        File.rm_rf!(tmp)
        :ok
      end)

      capture_log(fn ->
        assert {:error, {:invalid_archive_layout, :expected_single_top_level, entries}} =
                 ReleaseWorker.perform(%Oban.Job{
                   args: %{
                     "scope" => "apple",
                     "name" => "swift-argument-parser",
                     "repository_full_handle" => "apple/swift-argument-parser",
                     "tag" => "v1.0.0"
                   }
                 })

        assert Enum.sort(entries) == ["repo-v1.0.0", "repo-v1.0.1"]
      end)
    end
  end

  defp write_basic_zipball(archive_path) do
    tmp = Path.join(Path.dirname(archive_path), "zipball_content")
    top_dir = Path.join(tmp, "repo-v1.0.0")

    File.mkdir_p!(top_dir)
    File.write!(Path.join(top_dir, "Package.swift"), "// swift-tools-version:5.9")
    {_, 0} = System.cmd("zip", ["-r", archive_path, "repo-v1.0.0"], cd: tmp)
    File.rm_rf!(tmp)
  end

  defp expect_release_sync_prerequisites do
    expect(Lock, :try_acquire, fn {:release, "apple", "swift-argument-parser", "1.0.0"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(TuistCommon.GitHub, :get_file_content, fn "apple/swift-argument-parser",
                                                     "token",
                                                     ".gitmodules",
                                                     "v1.0.0",
                                                     _ ->
      {:error, :not_found}
    end)
  end

  defp expect_manifest_fetch(manifest_content) do
    expect(TuistCommon.GitHub, :list_repository_contents, fn "apple/swift-argument-parser", "token", "v1.0.0", _ ->
      {:ok, [%{"path" => "Package.swift", "type" => "file"}]}
    end)

    expect(TuistCommon.GitHub, :get_file_content, fn "apple/swift-argument-parser",
                                                     "token",
                                                     "Package.swift",
                                                     "v1.0.0",
                                                     _ ->
      {:ok, manifest_content}
    end)
  end

  defp expect_metadata_update_success do
    expect(Lock, :try_acquire, fn {:package, "apple", "swift-argument-parser"}, _ ->
      {:ok, :acquired}
    end)

    expect(Metadata, :get_package, fn "apple", "swift-argument-parser", [fresh: true] ->
      {:error, :not_found}
    end)

    expect(Metadata, :put_package, fn "apple", "swift-argument-parser", _metadata ->
      :ok
    end)
  end
end
