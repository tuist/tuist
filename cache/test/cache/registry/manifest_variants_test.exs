defmodule Cache.Registry.ManifestVariantsTest do
  use ExUnit.Case, async: true

  alias Cache.Registry.ManifestVariants

  test "parses alternate manifest filenames" do
    assert ManifestVariants.alternate_manifest?("Package@swift-6.swift")
    assert ManifestVariants.alternate_manifest?("Package@swift-6.0.swift")
    assert ManifestVariants.alternate_manifest?("Package@swift-6.0.0.swift")

    assert ManifestVariants.filename_swift_version("Package@swift-6.swift") == "6"
    assert ManifestVariants.filename_swift_version("Package@swift-6.0.swift") == "6.0"
    assert ManifestVariants.filename_swift_version("Package@swift-6.0.0.swift") == "6.0.0"
    assert ManifestVariants.filename_swift_version("Package.swift") == nil
  end

  test "drops alternates whose tools version canonicalizes to the default manifest" do
    assert ManifestVariants.linkable_alternates([
             %{"swift_version" => nil, "swift_tools_version" => "6.0"},
             %{"swift_version" => "6.0.0", "swift_tools_version" => "6.0.0"},
             %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}
           ]) == [
             %{"swift_version" => "5.9", "swift_tools_version" => "5.9"}
           ]

    assert ManifestVariants.linkable_alternates([
             %{"swift_version" => nil, "swift_tools_version" => "6"},
             %{"swift_version" => "6.0.0", "swift_tools_version" => "6.0.0"}
           ]) == []
  end

  test "keeps the first alternate when alternates canonicalize to the same tools version" do
    first_swift_six_manifest = %{"swift_version" => "6", "swift_tools_version" => "6"}

    assert ManifestVariants.linkable_alternates([
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
    malformed_tools_version = %{"swift_version" => "6.0-beta", "swift_tools_version" => "6.0.0-beta"}

    assert ManifestVariants.linkable_alternates([
             %{"swift_version" => nil, "swift_tools_version" => "6.0"},
             missing_tools_version,
             malformed_tools_version
           ]) == [
             missing_tools_version,
             malformed_tools_version
           ]
  end
end
