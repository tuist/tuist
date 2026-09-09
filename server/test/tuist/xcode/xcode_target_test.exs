defmodule Tuist.Xcode.XcodeTargetTest do
  use ExUnit.Case, async: true

  alias Tuist.Xcode.XcodeTarget

  test "keeps both snapshots associated with their own hash and preserves declared destinations" do
    target =
      XcodeTarget.changeset(UUIDv7.generate(), 1, UUIDv7.generate(), %{
        "name" => "Library",
        "destinations" => ["iphone", "ipad", "mac"],
        "binary_cache_metadata" => %{
          "hash" => "binary",
          "subhashes" => %{
            "destinations" => ["iPhone"],
            "project_settings" => "binary-settings",
            "embedded_product_references" => "embedded",
            "hashed_strings" => ["binary", "iPhone"]
          }
        },
        "selective_testing_metadata" => %{
          "hash" => "testing",
          "subhashes" => %{
            "destinations" => ["mac"],
            "project_settings" => "test-settings",
            "embedded_product_references" => "",
            "hashed_strings" => ["testing", "mac"]
          }
        }
      })

    binary = XcodeTarget.with_hash_inputs(target, :binary_cache)
    testing = XcodeTarget.with_hash_inputs(target, :selective_testing)
    assert binary.hash_inputs["destinations"] == ["iPhone"]
    assert testing.hash_inputs["destinations"] == ["mac"]
    assert binary.project_settings_hash == "binary-settings"
    assert testing.project_settings_hash == "test-settings"
    assert binary.hash_inputs["embedded_product_references"] == "embedded"
    assert testing.hash_inputs["embedded_product_references"] == ""
    assert binary.destinations == ["iphone", "ipad", "mac"]
  end

  test "historical components never imply declared destinations were hashed" do
    target = %XcodeTarget{binary_cache_hash: "old", destinations: ["iphone", "mac"], sources_hash: "sources"}
    result = XcodeTarget.with_hash_inputs(target, :binary_cache)
    assert result.sources_hash == "sources"
    assert result.hash_inputs["destinations"] == nil
    assert result.hash_inputs["hashed_strings"] == nil
    assert result.hash_inputs["embedded_product_references"] == nil
  end

  test "does not attribute ambiguous historical shared components to either hash" do
    target = %XcodeTarget{binary_cache_hash: "binary", selective_testing_hash: "testing", sources_hash: "ambiguous"}

    for purpose <- [:binary_cache, :selective_testing] do
      result = XcodeTarget.with_hash_inputs(target, purpose)
      assert result.sources_hash == ""
      refute Map.has_key?(result.hash_inputs, "sources")
    end
  end

  test "old incoming payloads preserve available components without inventing missing ones" do
    target =
      XcodeTarget.changeset(UUIDv7.generate(), 1, UUIDv7.generate(), %{
        "destinations" => ["iphone"],
        "selective_testing_metadata" => %{"hash" => "old", "subhashes" => %{"sources" => "sources"}}
      })

    result = XcodeTarget.with_hash_inputs(target, :selective_testing)
    assert result.sources_hash == "sources"
    assert result.hash_inputs["destinations"] == nil
    assert result.hash_inputs["embedded_product_references"] == nil
  end

  test "empty recorded inputs differ from unavailable historical data" do
    target = %XcodeTarget{
      binary_cache_hash_inputs:
        JSON.encode!(%{
          "destinations" => [],
          "hashed_strings" => [],
          "embedded_product_references" => ""
        })
    }

    assert XcodeTarget.with_hash_inputs(target, :binary_cache).hash_inputs == %{
             "destinations" => [],
             "hashed_strings" => [],
             "embedded_product_references" => ""
           }
  end
end
