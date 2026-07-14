defmodule TuistCommon.Registry.Swift.AlternateManifestTest do
  use ExUnit.Case, async: true

  alias TuistCommon.Registry.Swift.AlternateManifest

  describe "registry_manifest_path?/1" do
    test "accepts the default manifest" do
      assert AlternateManifest.registry_manifest_path?("Package.swift")
    end

    test "accepts alternate manifests" do
      assert AlternateManifest.registry_manifest_path?("Package@swift-5.swift")
      assert AlternateManifest.registry_manifest_path?("Package@swift-5.9.swift")
      assert AlternateManifest.registry_manifest_path?("Package@swift-5.9.1.swift")
    end

    test "rejects non-manifest paths" do
      refute AlternateManifest.registry_manifest_path?("README.md")
      refute AlternateManifest.registry_manifest_path?("Package@swift-5.9.1.2.swift")
      refute AlternateManifest.registry_manifest_path?("Package@swift-main.swift")
    end
  end

  describe "swift_version_from_filename/1" do
    test "returns nil for the default manifest" do
      refute AlternateManifest.swift_version_from_filename("Package.swift")
    end

    test "extracts the alternate manifest Swift version" do
      assert AlternateManifest.swift_version_from_filename("Package@swift-5.swift") == "5"
      assert AlternateManifest.swift_version_from_filename("Package@swift-5.9.swift") == "5.9"
      assert AlternateManifest.swift_version_from_filename("Package@swift-5.9.1.swift") == "5.9.1"
    end
  end

  describe "swift_tools_version/1" do
    test "extracts the tools version from manifest content" do
      assert AlternateManifest.swift_tools_version(
               "// swift-tools-version:5\nimport PackageDescription"
             ) == "5"

      assert AlternateManifest.swift_tools_version(
               "// swift-tools-version: 5.9\nimport PackageDescription"
             ) ==
               "5.9"

      assert AlternateManifest.swift_tools_version(
               "// swift-tools-version:5.9.1\nimport PackageDescription"
             ) ==
               "5.9.1"
    end

    test "returns nil when the manifest has no tools version" do
      refute AlternateManifest.swift_tools_version("import PackageDescription")
    end
  end

  describe "linkable_alternates/1" do
    test "drops alternates whose tools version canonicalizes to the default manifest" do
      assert AlternateManifest.linkable_alternates([
               %{"swift_version" => nil, "swift_tools_version" => "6.0"},
               %{"swift_version" => "6.0.0", "swift_tools_version" => "6.0.0"},
               %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}
             ]) == [
               %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}
             ]

      assert AlternateManifest.linkable_alternates([
               %{"swift_version" => nil, "swift_tools_version" => "6"},
               %{"swift_version" => "6.0.0", "swift_tools_version" => "6.0.0"}
             ]) == []
    end

    test "keeps the first alternate when alternates canonicalize to the same tools version" do
      first_swift_six_manifest = %{"swift_version" => "6", "swift_tools_version" => "6"}

      assert AlternateManifest.linkable_alternates([
               first_swift_six_manifest,
               %{"swift_version" => "6.0", "swift_tools_version" => "6.0"},
               %{"swift_version" => "6.0.0", "swift_tools_version" => "6.0.0"},
               %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}
             ]) == [
               first_swift_six_manifest,
               %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}
             ]
    end

    test "preserves alternates when tools versions are missing or malformed" do
      missing_tools_version = %{"swift_version" => "5.10", "swift_tools_version" => nil}

      malformed_tools_version = %{
        "swift_version" => "6.0-beta",
        "swift_tools_version" => "6.0.0-beta"
      }

      assert AlternateManifest.linkable_alternates([
               %{"swift_version" => nil, "swift_tools_version" => "6.0"},
               missing_tools_version,
               malformed_tools_version
             ]) == [
               missing_tools_version,
               malformed_tools_version
             ]
    end
  end

  describe "deduplicate_by_tools_version/1" do
    test "keeps default manifests and linkable alternates" do
      default_manifest = %{"swift_version" => nil, "swift_tools_version" => "6.0"}
      swift_five_manifest = %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}

      assert AlternateManifest.deduplicate_by_tools_version([
               default_manifest,
               %{"swift_version" => "6.0.0", "swift_tools_version" => "6.0.0"},
               swift_five_manifest
             ]) == [
               default_manifest,
               swift_five_manifest
             ]
    end
  end
end
