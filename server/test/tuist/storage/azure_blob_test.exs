defmodule Tuist.Storage.AzureBlobTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.Storage.AzureBlob

  @account_name "tuiststorage"
  @account_key Base.encode64("01234567890123456789012345678901")
  @container_name "tuist"
  @endpoint "https://tuiststorage.blob.core.windows.net"

  setup :verify_on_exit!

  setup do
    stub(Environment, :azure_storage_account_name, fn -> @account_name end)
    stub(Environment, :azure_storage_account_key, fn -> @account_key end)
    stub(Environment, :azure_blob_container_name, fn -> @container_name end)
    stub(Environment, :azure_blob_endpoint, fn -> @endpoint end)
    stub(Environment, :azure_blob_service_version, fn -> "2020-12-06" end)
    stub(Environment, :s3_receive_timeout, fn -> 60_000 end)
    stub(Environment, :s3_pool_timeout, fn -> 5_000 end)

    :ok
  end

  describe "generate_download_url/2" do
    test "generates a read SAS URL for the blob" do
      url = AzureBlob.generate_download_url("Account/Project/builds/build.zip", expires_in: 60)
      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      assert uri.scheme == "https"
      assert uri.host == "tuiststorage.blob.core.windows.net"
      assert uri.path == "/tuist/Account/Project/builds/build.zip"
      assert query["sp"] == "r"
      assert query["sr"] == "b"
      assert query["sv"] == "2020-12-06"
      assert query["spr"] == "https"
      assert is_binary(query["sig"])
    end
  end

  describe "generate_upload_url/2" do
    test "generates a write SAS URL for a block blob upload" do
      url = AzureBlob.generate_upload_url("icons/icon with space.png", expires_in: 60)
      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      assert uri.path == "/tuist/icons/icon%20with%20space.png"
      assert query["sp"] == "cw"
      assert query["sr"] == "b"
      assert is_binary(query["sig"])
    end
  end

  describe "multipart_generate_url/4" do
    test "generates a Put Block SAS URL with a deterministic block ID" do
      upload_id = "018f6a3c-b6bd-7d79-a2ef-67f6c7f09734"
      url = AzureBlob.multipart_generate_url("builds/build.zip", upload_id, 3, expires_in: 60)
      uri = URI.parse(url)
      query = URI.decode_query(uri.query)

      assert query["comp"] == "block"
      assert query["blockid"] == Base.encode64("#{upload_id}-0000000003")
      assert query["sp"] == "cw"
    end
  end

  describe "put_object/2" do
    test "sends a signed Put Blob request with the required blob type header" do
      expect(Req, :request, fn opts ->
        assert opts[:method] == :put
        assert opts[:url] == "#{@endpoint}/#{@container_name}/icons/icon.png"
        assert opts[:body] == "png"
        assert {"x-ms-blob-type", "BlockBlob"} in opts[:headers]

        assert Enum.any?(opts[:headers], fn {key, value} ->
                 key == "authorization" and String.starts_with?(value, "SharedKey #{@account_name}:")
               end)

        {:ok, %{status: 201, headers: [], body: ""}}
      end)

      assert %{status: 201} = AzureBlob.put_object("icons/icon.png", "png")
    end
  end

  describe "upload_file/3" do
    test "streams file chunks using the configured block size" do
      file_path = Path.join(System.tmp_dir!(), "azure-blob-upload-#{System.unique_integer([:positive])}")
      File.write!(file_path, "abcde")

      on_exit(fn ->
        File.rm(file_path)
      end)

      parent = self()

      stub(Req, :request, fn opts ->
        uri = URI.parse(opts[:url])
        query = URI.decode_query(uri.query || "")

        case query["comp"] do
          "block" -> send(parent, {:block, opts[:body]})
          "blocklist" -> send(parent, {:blocklist, opts[:body]})
        end

        {:ok, %{status: 201, headers: [], body: ""}}
      end)

      assert AzureBlob.upload_file(file_path, "builds/build.zip", block_size: 2) == :ok
      assert_received {:block, "ab"}
      assert_received {:block, "cd"}
      assert_received {:block, "e"}
      assert_received {:blocklist, blocklist}
      assert blocklist =~ "<BlockList>"
    end
  end

  describe "multipart_complete_upload/3" do
    test "commits deterministic block IDs in part order" do
      upload_id = "018f6a3c-b6bd-7d79-a2ef-67f6c7f09734"

      expect(Req, :request, fn opts ->
        assert opts[:method] == :put
        uri = URI.parse(opts[:url])
        assert URI.decode_query(uri.query)["comp"] == "blocklist"

        assert opts[:body] =~ "<Latest>#{Base.encode64("#{upload_id}-0000000001")}</Latest>"
        assert opts[:body] =~ "<Latest>#{Base.encode64("#{upload_id}-0000000002")}</Latest>"

        {:ok, %{status: 201, headers: [], body: ""}}
      end)

      assert AzureBlob.multipart_complete_upload("builds/build.zip", upload_id, [{2, "etag-2"}, {1, "etag-1"}]) == :ok
    end
  end

  describe "list_objects/2" do
    test "parses Azure Blob list responses into the S3-compatible shape used by retention" do
      body = """
      <?xml version="1.0" encoding="utf-8"?>
      <EnumerationResults>
        <Blobs>
          <Blob>
            <Name>org/project/builds/build.zip</Name>
            <Properties>
              <Last-Modified>Tue, 09 Jul 2024 12:34:56 GMT</Last-Modified>
            </Properties>
          </Blob>
        </Blobs>
        <NextMarker>next-page</NextMarker>
      </EnumerationResults>
      """

      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        uri = URI.parse(opts[:url])
        query = URI.decode_query(uri.query)
        assert query["restype"] == "container"
        assert query["comp"] == "list"
        assert query["prefix"] == "org/project"
        assert query["maxresults"] == "10"

        {:ok, %{status: 200, headers: [], body: body}}
      end)

      assert {:ok,
              %{
                body: %{
                  contents: [%{key: "org/project/builds/build.zip", last_modified: %DateTime{}}],
                  is_truncated: true,
                  next_continuation_token: "next-page"
                }
              }} = AzureBlob.list_objects(@container_name, prefix: "org/project", max_keys: 10)
    end
  end
end
