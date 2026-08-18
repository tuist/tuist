defmodule Tuist.Registry.S3Test do
  use ExUnit.Case, async: true
  use Mimic

  alias ExAws.Operation.S3, as: S3Operation
  alias ExAws.S3.Upload
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

  test "forwards object metadata to the upload so a stored digest can be read back" do
    config = [host: "registry.example.com"]
    upload = %Upload{src: [], bucket: "registry-bucket", path: "archive.zip", opts: []}

    expect(Registry, :registry_bucket, fn -> "registry-bucket" end)
    expect(Registry, :registry_s3_config, fn -> config end)
    expect(Upload, :stream_file, fn _path -> [] end)

    # The digest only survives the round trip if `:meta` reaches ExAws. Dropping
    # it silently is what made every read-back verification observe `nil`.
    #
    # `:unrelated` stands in for whatever option is added next: the defect was
    # the class "an option the caller set is discarded", not those two keys, so
    # pinning only the keys we already know about would not catch a repeat.
    expect(ExAws.S3, :upload, fn _stream, "registry-bucket", "archive.zip", opts ->
      assert Keyword.get(opts, :meta) == [{"sha256", "abc123"}]
      assert Keyword.get(opts, :content_type) == "application/zip"
      assert Keyword.get(opts, :unrelated) == :forwarded
      assert Keyword.get(opts, :timeout) == 120_000
      assert Keyword.get(opts, :max_concurrency) == 8
      upload
    end)

    expect(ExAws, :request, fn ^upload, ^config -> {:ok, %{status_code: 200}} end)

    assert :ok =
             S3.upload_file("archive.zip", "/tmp/archive.zip",
               content_type: "application/zip",
               meta: [{"sha256", "abc123"}],
               unrelated: :forwarded
             )
  end

  test "drops nil options so a default-bearing header builder is not handed nil" do
    config = [host: "registry.example.com"]
    upload = %Upload{src: [], bucket: "registry-bucket", path: "archive.zip", opts: []}

    expect(Registry, :registry_bucket, fn -> "registry-bucket" end)
    expect(Registry, :registry_s3_config, fn -> config end)
    expect(Upload, :stream_file, fn _path -> [] end)

    expect(ExAws.S3, :upload, fn _stream, "registry-bucket", "archive.zip", opts ->
      refute Keyword.has_key?(opts, :meta)
      refute Keyword.has_key?(opts, :content_type)
      upload
    end)

    expect(ExAws, :request, fn ^upload, ^config -> {:ok, %{status_code: 200}} end)

    assert :ok = S3.upload_file("archive.zip", "/tmp/archive.zip", content_type: nil, meta: nil)
  end

  test "unwraps single-value header lists so callers compare against a binary" do
    config = [host: "registry.example.com"]

    operation = %S3Operation{http_method: :head, bucket: "registry-bucket", path: "archive.zip", headers: %{}}
    consistent = %{operation | headers: %{"X-Tigris-Consistent" => "true"}}

    expect(Registry, :registry_bucket, fn -> "registry-bucket" end)
    expect(Registry, :registry_s3_config, fn -> config end)
    expect(ExAws.S3, :head_object, fn "registry-bucket", "archive.zip" -> operation end)

    # The HTTP client returns each value as a list. Left wrapped, a caller
    # pattern-matching on the digest never matches and reports a mismatch
    # against a value that looks correct.
    expect(ExAws, :request, fn ^consistent, ^config ->
      {:ok,
       %{
         status_code: 200,
         headers: [
           {"X-Amz-Meta-Sha256", ["abc123"]},
           {"ETag", ["\"etag\""]},
           {"Vary", ["Accept", "Accept-Encoding"]}
         ]
       }}
    end)

    assert {:ok, headers} = S3.head_object("archive.zip")
    assert Map.get(headers, "x-amz-meta-sha256") == "abc123"
    assert S3.etag_from_headers(headers) == "etag"

    # A header that genuinely repeats keeps its list rather than silently
    # collapsing to its first value.
    assert Map.get(headers, "vary") == ["Accept", "Accept-Encoding"]
  end

  describe "copy_object/2" do
    setup do
      config = [host: "registry.example.com"]

      stub(Registry, :registry_bucket, fn -> "registry-bucket" end)
      stub(Registry, :registry_s3_config, fn -> config end)

      stub(ExAws.S3, :put_object_copy, fn "registry-bucket", destination, "registry-bucket", source ->
        %S3Operation{
          http_method: :put,
          bucket: "registry-bucket",
          path: destination,
          headers: %{"x-amz-copy-source" => "/registry-bucket/" <> source}
        }
      end)

      :ok
    end

    test "succeeds when the response body reports a completed copy" do
      expect(ExAws, :request, fn _operation, _config ->
        {:ok,
         %{
           status_code: 200,
           body: ~s(<CopyObjectResult><ETag>"abc"</ETag></CopyObjectResult>)
         }}
      end)

      assert :ok = S3.copy_object("registry/swift/a/b/1.0.0/source_archive.zip", "registry/backups/a.zip")
    end

    # S3 answers CopyObject with 200 even when the copy fails partway through,
    # embedding the failure in the body. A status-only check reports a backup
    # that does not exist as taken, which is worse than no backup at all.
    test "fails when the response body carries an error despite the 200 status" do
      expect(ExAws, :request, fn _operation, _config ->
        {:ok,
         %{
           status_code: 200,
           body: ~s(<Error><Code>InternalError</Code><Message>We encountered an internal error</Message></Error>)
         }}
      end)

      assert {:error, {:copy_failed, "registry/swift/a.zip", "registry/backups/a.zip", _body}} =
               S3.copy_object("registry/swift/a.zip", "registry/backups/a.zip")
    end

    test "fails when the response body is not a copy result at all" do
      expect(ExAws, :request, fn _operation, _config -> {:ok, %{status_code: 200, body: ""}} end)

      assert {:error, {:copy_result_unrecognized, _source, _destination}} =
               S3.copy_object("registry/swift/a.zip", "registry/backups/a.zip")
    end

    test "reports a missing source object" do
      expect(ExAws, :request, fn _operation, _config -> {:ok, %{status_code: 404}} end)

      assert {:error, :not_found} = S3.copy_object("registry/swift/a.zip", "registry/backups/a.zip")
    end
  end
end
