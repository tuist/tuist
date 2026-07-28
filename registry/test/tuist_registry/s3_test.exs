defmodule TuistRegistry.S3Test do
  use ExUnit.Case
  use Mimic

  alias ExAws.Operation.S3, as: S3Operation
  alias TuistRegistry.S3

  setup :set_mimic_from_context

  setup do
    stub(TuistRegistry.Config, :registry_bucket, fn -> "test-registry-bucket" end)
    :ok
  end

  test "requests strongly consistent object-storage reads" do
    operation = %S3Operation{headers: %{"existing" => "header"}}

    expect(ExAws, :request, fn requested_operation ->
      assert requested_operation.headers == %{
               "existing" => "header",
               "X-Tigris-Consistent" => "true"
             }

      {:ok, :response}
    end)

    assert S3.request(operation) == {:ok, :response}
  end

  describe "presign_download_url/2" do
    test "signs the requested response content type" do
      key = "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"

      expect(ExAws.Config, :new, fn :s3 -> :config end)

      expect(ExAws.S3, :presigned_url, fn :config, :get, "test-registry-bucket", ^key, opts ->
        assert opts == [
                 expires_in: 600,
                 query_params: [{"response-content-type", "application/zip"}]
               ]

        {:ok, "https://s3.example.com/source_archive.zip?signed=true"}
      end)

      assert S3.presign_download_url(key, type: :registry, content_type: "application/zip") ==
               {:ok, "https://s3.example.com/source_archive.zip?signed=true"}
    end
  end

  describe "list_objects/2" do
    test "returns object keys for a prefix" do
      prefix = "registry/metadata/"

      expect(ExAws.S3, :list_objects_v2, fn "test-registry-bucket", opts ->
        assert Keyword.get(opts, :prefix) == prefix
        %S3Operation{path: prefix}
      end)

      expect(ExAws, :stream!, fn %S3Operation{} ->
        [
          %{key: "registry/metadata/apple/swift-argument-parser/index.json"},
          %{key: "registry/metadata/pointfreeco/swift-composable-architecture/index.json"}
        ]
      end)

      assert S3.list_objects(prefix, type: :registry) ==
               {:ok,
                [
                  "registry/metadata/apple/swift-argument-parser/index.json",
                  "registry/metadata/pointfreeco/swift-composable-architecture/index.json"
                ]}
    end
  end
end
