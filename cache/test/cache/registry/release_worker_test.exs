defmodule Cache.Registry.ReleaseWorkerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.Disk
  alias Cache.Registry.ReleaseWorker
  alias Cache.S3Transfers

  @moduletag capture_log: true

  setup :set_mimic_global

  setup do
    {:ok, storage_dir} = Briefly.create(directory: true)
    stub(Disk, :storage_dir, fn -> storage_dir end)
    {:ok, storage_dir: storage_dir}
  end

  describe "perform/1" do
    test "fetches releases and downloads source archives" do
      releases = [
        %{
          "version" => "1.0.0",
          "source_archive_url" => "https://example.com/archive.zip",
          "manifests" => []
        }
      ]

      stub(Req, :get, fn url, _opts ->
        if String.contains?(url, "/releases") do
          {:ok, %Req.Response{status: 200, body: releases}}
        else
          {:ok, %Req.Response{status: 200, body: "archive content"}}
        end
      end)

      expect(S3Transfers, :enqueue_registry_upload, fn key ->
        assert String.contains?(key, "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip")
        {:ok, %{}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end

    test "handles 404 response gracefully" do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 404}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "nonexistent"}})
    end

    test "returns error on HTTP failure" do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: "Internal Server Error"}}
      end)

      assert {:error, {:http_error, 500, "Internal Server Error"}} =
               ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end

    test "returns error on network failure" do
      expect(Req, :get, fn _url, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end

    test "handles releases with nested data structure" do
      releases = [%{"version" => "1.0.0", "source_archive_url" => "https://example.com/archive.zip", "manifests" => []}]

      stub(Req, :get, fn url, _opts ->
        if String.contains?(url, "/releases") do
          {:ok, %Req.Response{status: 200, body: %{"releases" => releases}}}
        else
          {:ok, %Req.Response{status: 200, body: "archive content"}}
        end
      end)

      expect(S3Transfers, :enqueue_registry_upload, fn _key ->
        {:ok, %{}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end

    test "handles releases with data key" do
      releases = [%{"version" => "1.0.0", "source_archive_url" => "https://example.com/archive.zip", "manifests" => []}]

      stub(Req, :get, fn url, _opts ->
        if String.contains?(url, "/releases") do
          {:ok, %Req.Response{status: 200, body: %{"data" => releases}}}
        else
          {:ok, %Req.Response{status: 200, body: "archive content"}}
        end
      end)

      expect(S3Transfers, :enqueue_registry_upload, fn _key ->
        {:ok, %{}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end

    test "skips releases without version" do
      releases = [
        %{"source_archive_url" => "https://example.com/archive.zip", "manifests" => []},
        %{"version" => "1.0.0", "source_archive_url" => "https://example.com/archive.zip", "manifests" => []}
      ]

      stub(Req, :get, fn url, _opts ->
        if String.contains?(url, "/releases") do
          {:ok, %Req.Response{status: 200, body: releases}}
        else
          {:ok, %Req.Response{status: 200, body: "archive content"}}
        end
      end)

      expect(S3Transfers, :enqueue_registry_upload, fn key ->
        assert String.contains?(key, "1.0.0")
        {:ok, %{}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end

    test "handles empty releases list" do
      expect(Req, :get, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: []}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end
  end

  describe "manifest handling" do
    test "downloads Package.swift manifests" do
      releases = [
        %{
          "version" => "1.0.0",
          "source_archive_url" => nil,
          "manifests" => [
            %{"swift_version" => nil, "url" => "https://example.com/Package.swift"},
            %{"swift_version" => "5.9", "url" => "https://example.com/Package@swift-5.9.swift"}
          ]
        }
      ]

      stub(Req, :get, fn url, _opts ->
        if String.contains?(url, "/releases") do
          {:ok, %Req.Response{status: 200, body: releases}}
        else
          {:ok, %Req.Response{status: 200, body: "// swift-tools-version:5.9"}}
        end
      end)

      expect(S3Transfers, :enqueue_registry_upload, 2, fn key ->
        assert String.contains?(key, "Package")
        {:ok, %{}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end

    test "generates correct manifest filenames" do
      releases = [
        %{
          "version" => "1.0.0",
          "source_archive_url" => nil,
          "manifests" => [
            %{"swift_version" => nil, "url" => "https://example.com/Package.swift"},
            %{"swift_version" => "5.9", "url" => "https://example.com/Package@swift-5.9.swift"}
          ]
        }
      ]

      stub(Req, :get, fn url, _opts ->
        if String.contains?(url, "/releases") do
          {:ok, %Req.Response{status: 200, body: releases}}
        else
          {:ok, %Req.Response{status: 200, body: "manifest content"}}
        end
      end)

      expect(S3Transfers, :enqueue_registry_upload, 2, fn key ->
        send(self(), {:uploaded_key, key})
        {:ok, %{}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})

      assert_received {:uploaded_key, key1}
      assert_received {:uploaded_key, key2}

      keys = [key1, key2]
      assert Enum.any?(keys, &String.ends_with?(&1, "Package.swift"))
      assert Enum.any?(keys, &String.ends_with?(&1, "Package@swift-5.9.swift"))
    end
  end

  describe "key normalization" do
    test "normalizes scope and name to lowercase" do
      releases = [
        %{
          "version" => "1.0.0",
          "source_archive_url" => "https://example.com/archive.zip",
          "manifests" => []
        }
      ]

      stub(Req, :get, fn url, _opts ->
        if String.contains?(url, "/releases") do
          {:ok, %Req.Response{status: 200, body: releases}}
        else
          {:ok, %Req.Response{status: 200, body: "archive content"}}
        end
      end)

      expect(S3Transfers, :enqueue_registry_upload, fn key ->
        assert key == "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
        {:ok, %{}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "Apple", "name" => "Swift-Argument-Parser"}})
    end

    test "normalizes version strings" do
      releases = [
        %{
          "version" => "v1.2",
          "source_archive_url" => "https://example.com/archive.zip",
          "manifests" => []
        }
      ]

      stub(Req, :get, fn url, _opts ->
        if String.contains?(url, "/releases") do
          {:ok, %Req.Response{status: 200, body: releases}}
        else
          {:ok, %Req.Response{status: 200, body: "archive content"}}
        end
      end)

      expect(S3Transfers, :enqueue_registry_upload, fn key ->
        assert String.contains?(key, "1.2.0")
        {:ok, %{}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end
  end

  describe "existing file handling" do
    test "enqueues upload for existing files without re-downloading" do
      releases = [
        %{
          "version" => "1.0.0",
          "source_archive_url" => "https://example.com/archive.zip",
          "manifests" => []
        }
      ]

      key = "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
      path = Disk.artifact_path(key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "existing content")

      expect(Req, :get, fn url, _opts ->
        if String.contains?(url, "/releases") do
          {:ok, %Req.Response{status: 200, body: releases}}
        else
          flunk("Should not download existing file")
        end
      end)

      expect(S3Transfers, :enqueue_registry_upload, fn ^key ->
        {:ok, %{}}
      end)

      assert :ok = ReleaseWorker.perform(%Oban.Job{args: %{"scope" => "apple", "name" => "swift-argument-parser"}})
    end
  end
end
