defmodule TuistCommon.Registry.Swift.MetadataTest do
  use ExUnit.Case, async: true

  alias TuistCommon.Registry.Swift.Metadata

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
    "skipped_releases" => %{
      "0.9.0" => %{"reason" => "invalid_archive"}
    },
    "updated_at" => "2024-01-15T10:30:00Z"
  }

  describe "s3_key/2" do
    test "normalizes the package scope and name" do
      assert Metadata.s3_key("Apple", "swift.argument.parser") ==
               "registry/metadata/apple/swift_argument_parser/index.json"
    end
  end

  describe "decode_package/1" do
    test "decodes valid metadata" do
      assert Metadata.decode_package(JSON.encode!(@sample_metadata)) == {:ok, @sample_metadata}
    end

    test "sanitizes invalid release versions" do
      dirty_metadata =
        @sample_metadata
        |> put_in(["releases", "0.0.24b"], %{"checksum" => "legacy"})
        |> put_in(["skipped_releases", "0.0.24b"], %{"reason" => "invalid_semver"})

      assert {:ok, metadata} = Metadata.decode_package(JSON.encode!(dirty_metadata))
      refute Map.has_key?(metadata["releases"], "0.0.24b")
      refute Map.has_key?(metadata["skipped_releases"], "0.0.24b")
    end

    test "rejects malformed JSON" do
      assert Metadata.decode_package("not json") == {:error, :invalid_metadata}
    end
  end

  describe "encode_package!/1" do
    test "sanitizes metadata before encoding" do
      dirty_metadata =
        @sample_metadata
        |> put_in(["releases", "0.0.24b"], %{"checksum" => "legacy"})
        |> put_in(["skipped_releases", "0.0.24b"], %{"reason" => "invalid_semver"})

      encoded = Metadata.encode_package!(dirty_metadata)
      metadata = JSON.decode!(encoded)

      refute Map.has_key?(metadata["releases"], "0.0.24b")
      refute Map.has_key?(metadata["skipped_releases"], "0.0.24b")
    end
  end

  describe "parse_s3_key/1" do
    test "returns package scope and name for metadata keys" do
      assert Metadata.parse_s3_key("registry/metadata/apple/swift-argument-parser/index.json") ==
               {"apple", "swift-argument-parser"}
    end

    test "rejects non-metadata keys" do
      refute Metadata.parse_s3_key("registry/metadata/apple/index.json")
      refute Metadata.parse_s3_key("registry/swift/apple/swift-argument-parser/index.json")
    end
  end
end
