defmodule Atlas.ObjectStorageTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.ObjectStorage

  @config %ObjectStorage{
    endpoint_url: "https://fsn1.your-objectstorage.com",
    region: "fsn1",
    bucket: "atlas-test",
    access_key_id: "access-key",
    secret_access_key: "secret-key"
  }

  test "put_object signs and stores an object" do
    Req
    |> expect(:request, fn request ->
      headers = Map.new(request[:headers])

      assert request[:method] == :put
      assert request[:url] == "https://fsn1.your-objectstorage.com/atlas-test/accounts/acme/logo.png"
      assert request[:body] == "image-bytes"
      assert headers["content-type"] == "image/png"
      assert headers["x-amz-content-sha256"] == sha256_hex("image-bytes")
      assert headers["authorization"] =~ "AWS4-HMAC-SHA256 Credential=access-key/"
      assert headers["authorization"] =~ "/fsn1/s3/aws4_request"
      assert headers["authorization"] =~ "SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date"

      {:ok, %{status: 200, body: "", headers: []}}
    end)

    assert {:ok, %{status: 200}} =
             ObjectStorage.put_object("accounts/acme/logo.png", "image-bytes",
               config: @config,
               content_type: "image/png"
             )
  end

  test "get_object returns the body and content type" do
    Req
    |> expect(:request, fn request ->
      assert request[:method] == :get
      assert request[:url] == "https://fsn1.your-objectstorage.com/atlas-test/library/notes/demo.txt"

      {:ok, %{status: 200, body: "hello", headers: [{"content-type", "text/plain"}]}}
    end)

    assert {:ok, %{body: "hello", content_type: "text/plain", key: "notes/demo.txt"}} =
             ObjectStorage.get_object("notes/demo.txt", config: @config)
  end

  test "delete_object accepts no-content responses" do
    Req
    |> expect(:request, fn request ->
      assert request[:method] == :delete
      assert request[:url] == "https://fsn1.your-objectstorage.com/atlas-test/library/notes/demo.txt"

      {:ok, %{status: 204, body: "", headers: []}}
    end)

    assert {:ok, %{status: 204}} = ObjectStorage.delete_object("notes/demo.txt", config: @config)
  end

  test "head_object checks object metadata without fetching a body" do
    Req
    |> expect(:request, fn request ->
      assert request[:method] == :head
      assert request[:url] == "https://fsn1.your-objectstorage.com/atlas-test/library/notes/demo.txt"

      {:ok, %{status: 200, body: "", headers: [{"content-type", "text/plain"}]}}
    end)

    assert {:ok, %{status: 200}} = ObjectStorage.head_object("notes/demo.txt", config: @config)
  end

  test "returns unexpected status errors with the response body" do
    Req
    |> expect(:request, fn request ->
      assert request[:method] == :get

      {:ok, %{status: 404, body: "missing", headers: []}}
    end)

    assert {:error, {:unexpected_status, 404, "missing"}} =
             ObjectStorage.get_object("notes/missing.txt", config: @config)
  end

  test "returns request failures" do
    Req
    |> expect(:request, fn request ->
      assert request[:method] == :get

      {:error, :timeout}
    end)

    assert {:error, :timeout} = ObjectStorage.get_object("notes/demo.txt", config: @config)
  end

  test "public_url returns a configured public base URL when available" do
    config = %{@config | public_base_url: "https://objects.tuist.dev/atlas"}

    assert {:ok, "https://objects.tuist.dev/atlas/folder/a%20b.txt"} =
             ObjectStorage.public_url("folder/a b.txt", config: config)
  end

  test "public_url falls back to the object URL" do
    assert {:ok, "https://fsn1.your-objectstorage.com/atlas-test/folder/a%20b.txt"} =
             ObjectStorage.public_url("folder/a b.txt", config: @config)
  end

  test "configured? returns false when required config is missing" do
    refute ObjectStorage.configured?(config: [])
  end

  defp sha256_hex(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end
end
