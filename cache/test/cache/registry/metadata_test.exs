defmodule Cache.Registry.MetadataTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.Registry.Metadata
  alias ExAws.Operation.S3

  setup :set_mimic_from_context

  @moduletag capture_log: true

  @sample_metadata %{
    "scope" => "apple",
    "name" => "swift-argument-parser",
    "repository_full_handle" => "apple/swift-argument-parser",
    "releases" => %{
      "1.2.0" => %{
        "checksum" => "abc123def456",
        "manifests" => [
          %{"swift_version" => nil, "swift_tools_version" => "5.7"},
          %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}
        ]
      }
    },
    "updated_at" => "2024-01-15T10:30:00Z"
  }

  setup do
    cache_name = :"registry_metadata_test_#{:erlang.unique_integer([:positive])}"
    start_supervised!({Cachex, name: cache_name})
    {:ok, cache_name: cache_name}
  end

  describe "child_spec/1" do
    test "returns valid child spec for Cachex" do
      spec = Metadata.child_spec([])

      assert spec.id == Metadata
      assert spec.start == {Cachex, :start_link, [:registry_metadata_cache, []]}
    end
  end

  describe "get_package/2" do
    test "returns metadata from cache when present", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"

      cached = %{
        metadata: @sample_metadata,
        etag: "some-etag",
        checked_at: DateTime.truncate(DateTime.utc_now(), :second)
      }

      Cachex.put(cache_name, {scope, name}, cached)

      assert {:ok, metadata} = Metadata.get_package(scope, name, cache_name: cache_name)
      assert metadata == @sample_metadata
    end

    test "fetches from S3 and caches when not in cache", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"
      json_body = Jason.encode!(@sample_metadata)

      expect(ExAws.S3, :get_object, fn "test-registry-bucket", ^s3_key ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:ok, %{body: json_body, headers: %{"etag" => "\"etag\""}}}
      end)

      assert {:ok, metadata} = Metadata.get_package(scope, name, cache_name: cache_name)
      assert metadata == @sample_metadata

      assert {:ok, cached} = Cachex.get(cache_name, {scope, name})
      assert cached.metadata == @sample_metadata
    end

    test "returns :not_found when S3 returns 404", %{cache_name: cache_name} do
      scope = "nonexistent"
      name = "package"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      expect(ExAws.S3, :get_object, fn "test-registry-bucket", ^s3_key ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:error, {:http_error, 404, "Not Found"}}
      end)

      assert {:error, :not_found} = Metadata.get_package(scope, name, cache_name: cache_name)
    end

    test "returns s3_error when S3 request fails with non-404 error", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      expect(ExAws.S3, :get_object, fn "test-registry-bucket", ^s3_key ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:error, :timeout}
      end)

      assert {:error, {:s3_error, :timeout}} = Metadata.get_package(scope, name, cache_name: cache_name)
    end

    test "returns s3_error with :rate_limited on 429 response", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      expect(ExAws.S3, :get_object, fn "test-registry-bucket", ^s3_key ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:error, {:http_error, 429, "Too Many Requests"}}
      end)

      assert {:error, {:s3_error, :rate_limited}} = Metadata.get_package(scope, name, cache_name: cache_name)
    end

    test "returns :not_found when JSON decode fails", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      expect(ExAws.S3, :get_object, fn "test-registry-bucket", ^s3_key ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:ok, %{body: "invalid json {", headers: %{"etag" => "\"etag\""}}}
      end)

      assert {:error, :not_found} = Metadata.get_package(scope, name, cache_name: cache_name)
    end
  end

  describe "put_package/3" do
    test "writes metadata to S3 and invalidates cache", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      Cachex.put(cache_name, {scope, name}, %{"old" => "data"})

      expect(ExAws.S3, :put_object, fn "test-registry-bucket", ^s3_key, body, opts ->
        assert Jason.decode!(body) == @sample_metadata
        assert Keyword.get(opts, :content_type) == "application/json"
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:ok, %{status_code: 200}}
      end)

      assert :ok = Metadata.put_package(scope, name, @sample_metadata, cache_name: cache_name)

      assert {:ok, nil} = Cachex.get(cache_name, {scope, name})
    end

    test "returns error when S3 write fails", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      expect(ExAws.S3, :put_object, fn "test-registry-bucket", ^s3_key, _body, _opts ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = Metadata.put_package(scope, name, @sample_metadata, cache_name: cache_name)
    end

    test "returns s3_error with :rate_limited on 429 response", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      expect(ExAws.S3, :put_object, fn "test-registry-bucket", ^s3_key, _body, _opts ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:error, {:http_error, 429, "Too Many Requests"}}
      end)

      assert {:error, {:s3_error, :rate_limited}} =
               Metadata.put_package(scope, name, @sample_metadata, cache_name: cache_name)
    end
  end

  describe "delete_package/2" do
    test "deletes from S3 and invalidates cache", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      Cachex.put(cache_name, {scope, name}, @sample_metadata)

      expect(ExAws.S3, :delete_object, fn "test-registry-bucket", ^s3_key ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:ok, %{status_code: 204}}
      end)

      assert :ok = Metadata.delete_package(scope, name, cache_name: cache_name)

      assert {:ok, nil} = Cachex.get(cache_name, {scope, name})
    end

    test "returns error when S3 delete fails", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      expect(ExAws.S3, :delete_object, fn "test-registry-bucket", ^s3_key ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:error, :access_denied}
      end)

      assert {:error, :access_denied} = Metadata.delete_package(scope, name, cache_name: cache_name)
    end

    test "returns s3_error with :rate_limited on 429 response", %{cache_name: cache_name} do
      scope = "apple"
      name = "swift-argument-parser"
      s3_key = "registry/metadata/#{scope}/#{name}/index.json"

      expect(ExAws.S3, :delete_object, fn "test-registry-bucket", ^s3_key ->
        %S3{bucket: "test-registry-bucket", path: s3_key}
      end)

      expect(ExAws, :request, fn %S3{} ->
        {:error, {:http_error, 429, "Too Many Requests"}}
      end)

      assert {:error, {:s3_error, :rate_limited}} = Metadata.delete_package(scope, name, cache_name: cache_name)
    end
  end

  describe "list_all_packages/0" do
    test "returns list of scope/name tuples from S3", %{cache_name: _cache_name} do
      expect(ExAws.S3, :list_objects_v2, fn "test-registry-bucket", opts ->
        assert Keyword.get(opts, :prefix) == "registry/metadata/"
        %S3{bucket: "test-registry-bucket", path: "registry/metadata/"}
      end)

      expect(ExAws, :stream!, fn %S3{} ->
        [
          %{key: "registry/metadata/apple/swift-argument-parser/index.json"},
          %{key: "registry/metadata/pointfreeco/swift-composable-architecture/index.json"},
          %{key: "registry/metadata/some-other-file.txt"}
        ]
      end)

      result = Metadata.list_all_packages()

      assert result == [
               {"apple", "swift-argument-parser"},
               {"pointfreeco", "swift-composable-architecture"}
             ]
    end

    test "returns empty list when no packages exist", %{cache_name: _cache_name} do
      expect(ExAws.S3, :list_objects_v2, fn "test-registry-bucket", _opts ->
        %S3{bucket: "test-registry-bucket", path: "registry/metadata/"}
      end)

      expect(ExAws, :stream!, fn %S3{} ->
        []
      end)

      assert Metadata.list_all_packages() == []
    end
  end
end
