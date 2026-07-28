defmodule Tuist.Registry.Swift.PurgeTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Registry.S3
  alias Tuist.Registry.Swift.Purge

  setup :verify_on_exit!

  describe "purge_package/2" do
    test "deletes artifact + metadata prefixes for the normalized scope/name" do
      expect(S3, :delete_all_with_prefix, fn "registry/swift/apple/swift_argument_parser/" -> {:ok, 42} end)
      expect(S3, :delete_all_with_prefix, fn "registry/metadata/apple/swift_argument_parser/" -> {:ok, 1} end)

      assert {:ok,
              %{
                scope: "apple",
                name: "swift_argument_parser",
                artifacts_deleted: 42,
                metadata_deleted: 1
              }} = Purge.purge_package("Apple", "swift.argument.parser")
    end

    test "surfaces S3 errors from the artifact delete" do
      expect(S3, :delete_all_with_prefix, fn "registry/swift/apple/parser/" -> {:error, :rate_limited} end)

      assert {:error, :rate_limited} = Purge.purge_package("apple", "parser")
    end
  end

  describe "purge_version/3" do
    test "removes the version from both releases and skipped_releases and writes updated metadata" do
      metadata = %{
        "releases" => %{"1.0.0" => %{"sha" => "deadbeef"}, "2.0.0" => %{}},
        "skipped_releases" => %{"1.0.0" => %{"reason" => "missing_default_manifest"}}
      }

      expect(S3, :delete_all_with_prefix, fn "registry/swift/apple/parser/1.0.0/" -> {:ok, 5} end)
      expect(S3, :get_object, fn "registry/metadata/apple/parser/index.json" -> {:ok, JSON.encode!(metadata)} end)

      expect(S3, :upload_content, fn key, body, opts ->
        assert key == "registry/metadata/apple/parser/index.json"
        assert opts == [content_type: "application/json"]
        decoded = JSON.decode!(body)
        assert decoded["releases"] == %{"2.0.0" => %{}}
        assert decoded["skipped_releases"] == %{}
        assert is_binary(decoded["updated_at"])
        :ok
      end)

      assert {:ok,
              %{
                scope: "apple",
                name: "parser",
                version: "1.0.0",
                artifacts_deleted: 5,
                metadata: %{removed_from: removed_from}
              }} = Purge.purge_version("Apple", "Parser", "1.0.0")

      assert Enum.sort(removed_from) == ["releases", "skipped_releases"]
    end

    test "normalizes the version before touching S3" do
      expect(S3, :delete_all_with_prefix, fn "registry/swift/apple/parser/1.2.0/" -> {:ok, 0} end)
      expect(S3, :get_object, fn _key -> {:error, :not_found} end)

      assert {:ok, %{version: "1.2.0", metadata: :metadata_absent}} = Purge.purge_version("apple", "parser", "v1.2")
    end

    test "returns :not_present when the version is missing from metadata, without writing back" do
      metadata = %{"releases" => %{"3.0.0" => %{}}, "skipped_releases" => %{}}

      expect(S3, :delete_all_with_prefix, fn _ -> {:ok, 0} end)
      expect(S3, :get_object, fn _ -> {:ok, JSON.encode!(metadata)} end)
      reject(&S3.upload_content/3)

      assert {:ok, %{metadata: :not_present}} = Purge.purge_version("apple", "parser", "9.9.9")
    end

    test "returns :metadata_absent when no metadata exists, without writing back" do
      expect(S3, :delete_all_with_prefix, fn _ -> {:ok, 0} end)
      expect(S3, :get_object, fn _ -> {:error, :not_found} end)
      reject(&S3.upload_content/3)

      assert {:ok, %{metadata: :metadata_absent}} = Purge.purge_version("apple", "parser", "1.0.0")
    end

    test "surfaces malformed metadata JSON as a tagged error" do
      expect(S3, :delete_all_with_prefix, fn _ -> {:ok, 0} end)
      expect(S3, :get_object, fn _ -> {:ok, "not json"} end)

      assert {:error, {:invalid_metadata_json, _}} = Purge.purge_version("apple", "parser", "1.0.0")
    end
  end
end
