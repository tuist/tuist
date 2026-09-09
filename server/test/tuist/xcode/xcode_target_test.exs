defmodule Tuist.Xcode.XcodeTargetTest do
  use ExUnit.Case, async: true

  alias Tuist.Xcode.XcodeTarget

  for purpose <- ["binary_cache_metadata", "selective_testing_metadata"] do
    test "stores individual inputs from #{purpose} separately from declared destinations" do
      target =
        XcodeTarget.changeset(UUIDv7.generate(), 1, UUIDv7.generate(), %{
          "name" => "Target",
          "destinations" => ["iphone", "ipad", "mac"],
          unquote(purpose) => %{
            "hash" => "hash",
            "subhashes" => %{
              "destinations" => ["iPhone"],
              "project_settings" => "settings",
              "embedded_product_references" => "embedded",
              "foreign_build" => "foreign",
              "test_device" => "iPhone 16",
              "test_runtime" => "iOS-16"
            }
          }
        })

      assert XcodeTarget.hashed_destinations(target) == ["iPhone"]
      assert target.project_settings_hash == "settings"
      assert target.embedded_product_references_hash == "embedded"
      assert target.foreign_build_hash == "foreign"
      assert target.test_device == "iPhone 16"
      assert target.test_runtime == "iOS-16"
      assert target.destinations == ["iphone", "ipad", "mac"]
    end
  end

  test "historical rows retain components without inventing missing inputs" do
    target = %XcodeTarget{destinations: ["iphone", "mac"], sources_hash: "sources"}
    assert target.sources_hash == "sources"
    assert XcodeTarget.hashed_destinations(target) == nil
    assert target.embedded_product_references_hash == nil
    assert target.foreign_build_hash == nil
    assert target.test_device == nil
    assert target.test_runtime == nil
  end

  test "old incoming payloads preserve available components" do
    target =
      XcodeTarget.changeset(UUIDv7.generate(), 1, UUIDv7.generate(), %{
        "destinations" => ["iphone"],
        "selective_testing_metadata" => %{"hash" => "old", "subhashes" => %{"sources" => "sources"}}
      })

    assert target.sources_hash == "sources"
    assert XcodeTarget.hashed_destinations(target) == nil
    assert target.embedded_product_references_hash == nil
    assert target.foreign_build_hash == nil
  end

  test "empty recorded inputs differ from unavailable historical data" do
    target =
      XcodeTarget.changeset(UUIDv7.generate(), 1, UUIDv7.generate(), %{
        "binary_cache_metadata" => %{
          "hash" => "hash",
          "subhashes" => %{
            "destinations" => [],
            "embedded_product_references" => "",
            "foreign_build" => "",
            "test_device" => "",
            "test_runtime" => ""
          }
        }
      })

    assert XcodeTarget.hashed_destinations(target) == []
    assert target.embedded_product_references_hash == ""
    assert target.foreign_build_hash == ""
    assert target.test_device == ""
    assert target.test_runtime == ""
  end
end
