defmodule Tuist.Registry.S3Test do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAws.Operation.S3, as: S3Operation
  alias Tuist.Registry
  alias Tuist.Registry.S3

  setup :set_mimic_from_context

  test "reads with the dedicated registry object-storage configuration" do
    config = [
      host: "registry.example.com",
      access_key_id: "registry-access-key",
      secret_access_key: "registry-secret-key"
    ]

    operation = %S3Operation{
      http_method: :get,
      bucket: "registry-bucket",
      path: "registry/metadata/adjust/ios_sdk/index.json"
    }

    expect(Registry, :registry_bucket, fn -> "registry-bucket" end)
    expect(Registry, :registry_s3_config, fn -> config end)

    expect(ExAws.S3, :get_object, fn "registry-bucket", "registry/metadata/adjust/ios_sdk/index.json" ->
      operation
    end)

    expect(ExAws, :request, fn ^operation, ^config ->
      {:ok, %{status_code: 200, body: ~s({"releases":{}})}}
    end)

    assert {:ok, ~s({"releases":{}})} =
             S3.get_object("registry/metadata/adjust/ios_sdk/index.json")
  end

  test "downloads an existing archive with the dedicated registry object-storage configuration" do
    config = [host: "registry.example.com"]
    key = "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
    local_path = "/tmp/source_archive.zip"
    head_operation = %S3Operation{http_method: :head, bucket: "registry-bucket", path: key}

    download_operation = %ExAws.S3.Download{
      bucket: "registry-bucket",
      path: key,
      dest: local_path
    }

    stub(Registry, :registry_bucket, fn -> "registry-bucket" end)
    stub(Registry, :registry_s3_config, fn -> config end)

    expect(ExAws.S3, :head_object, fn "registry-bucket", ^key -> head_operation end)

    expect(ExAws.S3, :download_file, fn "registry-bucket", ^key, ^local_path, opts ->
      assert opts == [timeout: 120_000, max_concurrency: 8]
      download_operation
    end)

    expect(ExAws, :request, 2, fn
      ^head_operation, ^config -> {:ok, %{status_code: 200}}
      ^download_operation, ^config -> {:ok, :done}
    end)

    assert :ok = S3.download_file(key, local_path)
  end

  test "does not start a download when the archive is missing" do
    key = "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
    head_operation = %S3Operation{http_method: :head, bucket: "registry-bucket", path: key}

    stub(Registry, :registry_bucket, fn -> "registry-bucket" end)
    stub(Registry, :registry_s3_config, fn -> [host: "registry.example.com"] end)
    expect(ExAws.S3, :head_object, fn "registry-bucket", ^key -> head_operation end)
    expect(ExAws, :request, fn ^head_operation, _ -> {:error, {:http_error, 404, ""}} end)
    stub(ExAws.S3, :download_file, fn _, _, _, _ -> flunk("unexpected download") end)

    assert {:error, :not_found} = S3.download_file(key, "/tmp/source_archive.zip")
  end
end
