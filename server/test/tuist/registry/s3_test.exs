defmodule Tuist.Registry.S3Test do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAws.Operation.S3, as: S3Operation
  alias Tuist.Registry
  alias Tuist.Registry.S3

  setup :set_mimic_from_context

  test "uses the dedicated registry object-storage configuration and consistent reads" do
    config = [
      host: "registry.example.com",
      access_key_id: "registry-access-key",
      secret_access_key: "registry-secret-key"
    ]

    operation = %S3Operation{
      http_method: :get,
      bucket: "registry-bucket",
      path: "registry/metadata/adjust/ios_sdk/index.json",
      headers: %{}
    }

    consistent_operation = %{operation | headers: %{"X-Tigris-Consistent" => "true"}}

    expect(Registry, :registry_bucket, fn -> "registry-bucket" end)
    expect(Registry, :registry_s3_config, fn -> config end)

    expect(ExAws.S3, :get_object, fn "registry-bucket", "registry/metadata/adjust/ios_sdk/index.json" ->
      operation
    end)

    expect(ExAws, :request, fn ^consistent_operation, ^config ->
      {:ok, %{status_code: 200, body: ~s({"releases":{}})}}
    end)

    assert {:ok, ~s({"releases":{}})} =
             S3.get_object("registry/metadata/adjust/ios_sdk/index.json")
  end

  test "uses consistent writes" do
    config = [host: "registry.example.com"]

    operation = %S3Operation{
      http_method: :put,
      bucket: "registry-bucket",
      path: "registry/swift/adjust/ios_sdk/1.0.0/source_archive.zip",
      headers: %{}
    }

    consistent_operation = %{operation | headers: %{"X-Tigris-Consistent" => "true"}}

    expect(Registry, :registry_s3_config, fn -> config end)

    expect(ExAws, :request, fn ^consistent_operation, ^config ->
      {:ok, %{status_code: 200}}
    end)

    assert {:ok, %{status_code: 200}} = S3.request(operation)
  end
end
