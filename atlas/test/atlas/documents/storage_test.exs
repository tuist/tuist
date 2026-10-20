defmodule Atlas.Documents.StorageTest do
  use ExUnit.Case, async: true

  alias Atlas.Documents.Storage

  describe "delegation to the configured client" do
    test "bucket/0 returns the configured client's bucket" do
      assert Storage.bucket() == "test-documents"
    end

    test "put_object/3 then get_object/2 round-trips the body" do
      key = "documents/test/#{System.unique_integer([:positive])}.pdf"

      assert {:ok, %{bucket: "test-documents", key: ^key}} = Storage.put_object(key, "the bytes")
      assert {:ok, %{body: "the bytes", key: ^key}} = Storage.get_object(key)
    end

    test "get_object/2 surfaces the client's error for a missing key" do
      assert {:error, :not_found} = Storage.get_object("documents/missing.pdf")
    end
  end

  describe "configured?/0" do
    test "is true when the client reports a non-empty bucket" do
      assert Storage.configured?()
    end
  end

  describe "presigned_get_url/2" do
    test "falls back to :not_supported when the client cannot sign URLs" do
      assert {:error, :not_supported} = Storage.presigned_get_url("documents/whatever.pdf")
    end
  end
end
