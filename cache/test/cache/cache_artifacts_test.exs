defmodule Cache.CacheArtifactsTest do
  use ExUnit.Case, async: true

  alias Cache.CacheArtifacts

  describe "encode_module/3" do
    test "encodes category, hash, and name into module artifact ID" do
      assert CacheArtifacts.encode_module("builds", "abc123", "MyModule.xcframework.zip") ==
               "module::builds::abc123::MyModule.xcframework.zip"
    end

    test "handles empty strings" do
      assert CacheArtifacts.encode_module("", "", "") == "module::::::"
    end

    test "handles special characters in name" do
      assert CacheArtifacts.encode_module("builds", "hash", "My Module (1).zip") ==
               "module::builds::hash::My Module (1).zip"
    end
  end

  describe "decode/1" do
    test "decodes module artifact ID into tagged tuple" do
      assert CacheArtifacts.decode("module::builds::abc123::MyModule.xcframework.zip") ==
               {:module, "builds", "abc123", "MyModule.xcframework.zip"}
    end

    test "decodes CAS artifact ID into tagged tuple" do
      assert CacheArtifacts.decode("abc123def456") == {:cas, "abc123def456"}
    end

    test "handles module artifact with colons in name" do
      assert CacheArtifacts.decode("module::builds::hash::file::with::colons.zip") ==
               {:module, "builds", "hash", "file::with::colons.zip"}
    end

    test "roundtrips module artifact IDs" do
      original = CacheArtifacts.encode_module("custom_category", "deadbeef", "Test.framework.zip")
      assert {:module, "custom_category", "deadbeef", "Test.framework.zip"} = CacheArtifacts.decode(original)
    end

    test "does not decode strings that start with 'module' but not 'module::'" do
      assert CacheArtifacts.decode("moduleabc123") == {:cas, "moduleabc123"}
    end
  end
end
