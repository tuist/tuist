defmodule Cache.Registry.AlternateManifestsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.Config
  alias Cache.Registry.AlternateManifests
  alias ExAws.Operation.S3

  setup :set_mimic_from_context

  setup do
    cache_name = :"alternate_manifests_test_#{:erlang.unique_integer([:positive])}"
    start_supervised!({Cachex, name: cache_name})
    stub(Config, :registry_bucket, fn -> "test-bucket" end)
    {:ok, cache_name: cache_name}
  end

  test "discovers alternate manifests and reads swift_tools_version from each file",
       %{cache_name: cache_name} do
    scope = "mxcl"
    name = "promisekit"
    version = "6.18.1"

    expect(ExAws.S3, :list_objects_v2, fn "test-bucket", opts ->
      assert Keyword.get(opts, :prefix) == "registry/swift/#{scope}/#{name}/#{version}/"
      %S3{bucket: "test-bucket", path: "list"}
    end)

    expect(ExAws, :stream!, fn %S3{path: "list"} ->
      [
        %{key: "registry/swift/#{scope}/#{name}/#{version}/Package.swift"},
        %{key: "registry/swift/#{scope}/#{name}/#{version}/Package@swift-4.2.swift"},
        %{key: "registry/swift/#{scope}/#{name}/#{version}/Package@swift-5.0.swift"},
        %{key: "registry/swift/#{scope}/#{name}/#{version}/Package@swift-5.3.swift"},
        %{key: "registry/swift/#{scope}/#{name}/#{version}/source_archive.zip"}
      ]
    end)

    expect(ExAws.S3, :get_object, 3, fn "test-bucket", key ->
      %S3{bucket: "test-bucket", path: key}
    end)

    expect(ExAws, :request, 3, fn %S3{path: path} ->
      tools_version =
        cond do
          String.ends_with?(path, "/Package@swift-4.2.swift") -> "4.2"
          String.ends_with?(path, "/Package@swift-5.0.swift") -> "5.0"
          String.ends_with?(path, "/Package@swift-5.3.swift") -> "5.3"
        end

      {:ok, %{body: "// swift-tools-version:#{tools_version}\n"}}
    end)

    manifests = AlternateManifests.list(scope, name, version, cache_name: cache_name)

    assert manifests == [
             %{"swift_version" => "4.2", "swift_tools_version" => "4.2"},
             %{"swift_version" => "5.0", "swift_tools_version" => "5.0"},
             %{"swift_version" => "5.3", "swift_tools_version" => "5.3"}
           ]
  end

  test "caches results across calls so S3 is hit only once", %{cache_name: cache_name} do
    expect(ExAws.S3, :list_objects_v2, 1, fn "test-bucket", _opts ->
      %S3{bucket: "test-bucket", path: "list"}
    end)

    expect(ExAws, :stream!, 1, fn %S3{path: "list"} ->
      [%{key: "registry/swift/apple/swift-collections/1.3.0/Package@swift-6.0.swift"}]
    end)

    expect(ExAws.S3, :get_object, 1, fn "test-bucket", key ->
      %S3{bucket: "test-bucket", path: key}
    end)

    expect(ExAws, :request, 1, fn %S3{} ->
      {:ok, %{body: "// swift-tools-version:6.0\n"}}
    end)

    first =
      AlternateManifests.list("apple", "swift-collections", "1.3.0", cache_name: cache_name)

    second =
      AlternateManifests.list("apple", "swift-collections", "1.3.0", cache_name: cache_name)

    assert first == second
    assert first == [%{"swift_version" => "6.0", "swift_tools_version" => "6.0"}]
  end

  test "returns empty list when only the root Package.swift is present",
       %{cache_name: cache_name} do
    expect(ExAws.S3, :list_objects_v2, fn "test-bucket", _opts ->
      %S3{bucket: "test-bucket", path: "list"}
    end)

    expect(ExAws, :stream!, fn %S3{} ->
      [
        %{key: "registry/swift/foo/bar/1.0.0/Package.swift"},
        %{key: "registry/swift/foo/bar/1.0.0/source_archive.zip"}
      ]
    end)

    assert AlternateManifests.list("foo", "bar", "1.0.0", cache_name: cache_name) == []
  end

  test "skips manifest files that fail to fetch", %{cache_name: cache_name} do
    expect(ExAws.S3, :list_objects_v2, fn "test-bucket", _opts ->
      %S3{bucket: "test-bucket", path: "list"}
    end)

    expect(ExAws, :stream!, fn %S3{} ->
      [
        %{key: "registry/swift/foo/bar/1.0.0/Package@swift-5.3.swift"},
        %{key: "registry/swift/foo/bar/1.0.0/Package@swift-6.0.swift"}
      ]
    end)

    expect(ExAws.S3, :get_object, 2, fn "test-bucket", key ->
      %S3{bucket: "test-bucket", path: key}
    end)

    expect(ExAws, :request, 2, fn %S3{path: path} ->
      if String.ends_with?(path, "/Package@swift-5.3.swift") do
        {:ok, %{body: "// swift-tools-version:5.3\n"}}
      else
        {:error, {:http_error, 500, %{}}}
      end
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert AlternateManifests.list("foo", "bar", "1.0.0", cache_name: cache_name) ==
                 [%{"swift_version" => "5.3", "swift_tools_version" => "5.3"}]
      end)

    assert log =~ "Failed to fetch alternate manifest"
  end

  test "returns empty list and logs warning when S3 raises", %{cache_name: cache_name} do
    expect(ExAws.S3, :list_objects_v2, fn "test-bucket", _opts ->
      %S3{bucket: "test-bucket", path: "list"}
    end)

    expect(ExAws, :stream!, fn %S3{} -> raise "boom" end)

    assert ExUnit.CaptureLog.capture_log(fn ->
             assert AlternateManifests.list("foo", "bar", "1.0.0", cache_name: cache_name) == []
           end) =~ "Failed to discover alternate manifests"
  end
end
