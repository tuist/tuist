defmodule Cache.Registry.KeyNormalizerTest do
  use ExUnit.Case, async: true

  alias Cache.Registry.KeyNormalizer

  describe "normalize_scope/1" do
    test "downcases uppercase scope" do
      assert KeyNormalizer.normalize_scope("Apple") == "apple"
    end

    test "downcases all-caps scope" do
      assert KeyNormalizer.normalize_scope("SWIFT") == "swift"
    end

    test "keeps lowercase scope unchanged" do
      assert KeyNormalizer.normalize_scope("swift") == "swift"
    end

    test "handles mixed case" do
      assert KeyNormalizer.normalize_scope("SwiftNIO") == "swiftnio"
    end
  end

  describe "normalize_version/1" do
    test "strips leading v prefix" do
      assert KeyNormalizer.normalize_version("v1.2.3") == "1.2.3"
    end

    test "adds trailing zeros for single digit version" do
      assert KeyNormalizer.normalize_version("1") == "1.0.0"
    end

    test "adds trailing zero for two-part version" do
      assert KeyNormalizer.normalize_version("1.2") == "1.2.0"
    end

    test "keeps three-part version unchanged" do
      assert KeyNormalizer.normalize_version("1.2.3") == "1.2.3"
    end

    test "strips v and adds zeros" do
      assert KeyNormalizer.normalize_version("v1") == "1.0.0"
      assert KeyNormalizer.normalize_version("v1.2") == "1.2.0"
    end

    test "converts pre-release dot to plus" do
      assert KeyNormalizer.normalize_version("1.0.0-alpha.1") == "1.0.0-alpha+1"
    end

    test "handles pre-release with v prefix" do
      assert KeyNormalizer.normalize_version("v2.0.0-beta.2") == "2.0.0-beta+2"
    end

    test "handles pre-release without dot" do
      assert KeyNormalizer.normalize_version("1.0.0-alpha") == "1.0.0-alpha"
    end

    test "handles incomplete version with pre-release" do
      assert KeyNormalizer.normalize_version("1-alpha.1") == "1.0.0-alpha+1"
    end

    test "handles multiple dots in pre-release" do
      assert KeyNormalizer.normalize_version("1.0.0-alpha.1.2") == "1.0.0-alpha+1+2"
    end

    test "strips leading zeros from version components" do
      assert KeyNormalizer.normalize_version("137.7151.04") == "137.7151.4"
    end

    test "strips leading zeros from all components" do
      assert KeyNormalizer.normalize_version("01.02.03") == "1.2.3"
    end

    test "preserves zero when not a leading zero" do
      assert KeyNormalizer.normalize_version("0.1.0") == "0.1.0"
    end

    test "strips v prefix and leading zeros" do
      assert KeyNormalizer.normalize_version("v01.2.3") == "1.2.3"
    end

    test "strips leading zeros from multi-digit components" do
      assert KeyNormalizer.normalize_version("10.020.003") == "10.20.3"
    end

    test "handles all-zero version" do
      assert KeyNormalizer.normalize_version("00.00.00") == "0.0.0"
    end

    test "strips leading zero from single component" do
      assert KeyNormalizer.normalize_version("01") == "1.0.0"
    end

    test "strips leading zeros from two components" do
      assert KeyNormalizer.normalize_version("01.02") == "1.2.0"
    end
  end

  describe "package_object_key/2" do
    test "constructs full key with version and path" do
      result =
        KeyNormalizer.package_object_key(
          %{scope: "Apple", name: "Parser"},
          version: "v1.2",
          path: "source_archive.zip"
        )

      assert result == "registry/swift/apple/parser/1.2.0/source_archive.zip"
    end

    test "downcases scope and name" do
      result =
        KeyNormalizer.package_object_key(
          %{scope: "SWIFT", name: "NIO"},
          version: "2.0.0",
          path: "Package.swift"
        )

      assert result == "registry/swift/swift/nio/2.0.0/Package.swift"
    end

    test "normalizes version in key" do
      result =
        KeyNormalizer.package_object_key(
          %{scope: "apple", name: "swift-syntax"},
          version: "v5.9",
          path: "source_archive.zip"
        )

      assert result == "registry/swift/apple/swift-syntax/5.9.0/source_archive.zip"
    end

    test "handles pre-release version" do
      result =
        KeyNormalizer.package_object_key(
          %{scope: "apple", name: "swift-syntax"},
          version: "1.0.0-alpha.1",
          path: "source_archive.zip"
        )

      assert result == "registry/swift/apple/swift-syntax/1.0.0-alpha+1/source_archive.zip"
    end

    test "constructs key without version" do
      result = KeyNormalizer.package_object_key(%{scope: "Apple", name: "Parser"}, [])
      assert result == "registry/swift/apple/parser"
    end

    test "constructs key with version but no path" do
      result =
        KeyNormalizer.package_object_key(
          %{scope: "Apple", name: "Parser"},
          version: "1.0.0"
        )

      assert result == "registry/swift/apple/parser/1.0.0"
    end

    test "constructs key without options" do
      result = KeyNormalizer.package_object_key(%{scope: "Apple", name: "Parser"})
      assert result == "registry/swift/apple/parser"
    end

    test "replaces dots with underscores in name" do
      result =
        KeyNormalizer.package_object_key(
          %{scope: "apple", name: "swift.argument.parser"},
          version: "1.0.0",
          path: "source_archive.zip"
        )

      assert result == "registry/swift/apple/swift_argument_parser/1.0.0/source_archive.zip"
    end

    test "normalizes leading zeros in version for object key" do
      result =
        KeyNormalizer.package_object_key(
          %{scope: "livekit", name: "webrtc-xcframework"},
          version: "137.7151.04",
          path: "source_archive.zip"
        )

      assert result == "registry/swift/livekit/webrtc-xcframework/137.7151.4/source_archive.zip"
    end
  end

  describe "normalize_name/1" do
    test "replaces dots with underscores" do
      assert KeyNormalizer.normalize_name("swift.argument.parser") == "swift_argument_parser"
    end

    test "downcases name" do
      assert KeyNormalizer.normalize_name("SwiftNIO") == "swiftnio"
    end

    test "handles name with dots and mixed case" do
      assert KeyNormalizer.normalize_name("Swift.Argument.Parser") == "swift_argument_parser"
    end

    test "keeps already-normalized name unchanged" do
      assert KeyNormalizer.normalize_name("swift-argument-parser") == "swift-argument-parser"
    end
  end

  describe "normalize_scope_name/2" do
    test "normalizes both scope and name" do
      assert KeyNormalizer.normalize_scope_name("Apple", "swift.argument.parser") ==
               {"apple", "swift_argument_parser"}
    end

    test "keeps already-normalized values" do
      assert KeyNormalizer.normalize_scope_name("apple", "swift-nio") ==
               {"apple", "swift-nio"}
    end
  end
end
