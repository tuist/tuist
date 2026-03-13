defmodule Tuist.Shards.PlistFilterTest do
  use ExUnit.Case, async: true

  alias Tuist.Shards.PlistFilter

  @sample_xctestrun """
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>TestConfigurations</key>
    <array>
      <dict>
        <key>Name</key>
        <string>Default</string>
        <key>TestTargets</key>
        <array>
          <dict>
            <key>BlueprintName</key>
            <string>AppTests</string>
            <key>TestBundlePath</key>
            <string>__TESTROOT__/AppTests.xctest</string>
          </dict>
          <dict>
            <key>BlueprintName</key>
            <string>CoreTests</string>
            <key>TestBundlePath</key>
            <string>__TESTROOT__/CoreTests.xctest</string>
          </dict>
          <dict>
            <key>BlueprintName</key>
            <string>NetworkTests</string>
            <key>TestBundlePath</key>
            <string>__TESTROOT__/NetworkTests.xctest</string>
          </dict>
        </array>
      </dict>
    </array>
    <key>__xctestrun_metadata__</key>
    <dict>
      <key>FormatVersion</key>
      <integer>2</integer>
    </dict>
  </dict>
  </plist>
  """

  describe "filter_xctestrun/3 module-level" do
    test "keeps only assigned targets" do
      result = PlistFilter.filter_xctestrun(@sample_xctestrun, ["AppTests", "CoreTests"], :module)

      assert result =~ "AppTests"
      assert result =~ "CoreTests"
      refute result =~ "NetworkTests"
    end

    test "keeps all targets when all are assigned" do
      result =
        PlistFilter.filter_xctestrun(
          @sample_xctestrun,
          ["AppTests", "CoreTests", "NetworkTests"],
          :module
        )

      assert result =~ "AppTests"
      assert result =~ "CoreTests"
      assert result =~ "NetworkTests"
    end

    test "removes all targets when none are assigned" do
      result = PlistFilter.filter_xctestrun(@sample_xctestrun, [], :module)

      refute result =~ "AppTests"
      refute result =~ "CoreTests"
      refute result =~ "NetworkTests"
    end

    test "preserves metadata" do
      result = PlistFilter.filter_xctestrun(@sample_xctestrun, ["AppTests"], :module)

      assert result =~ "__xctestrun_metadata__"
      assert result =~ "FormatVersion"
    end

    test "preserves XML declaration" do
      result = PlistFilter.filter_xctestrun(@sample_xctestrun, ["AppTests"], :module)

      assert result =~ "<?xml"
    end

    test "single target selection" do
      result = PlistFilter.filter_xctestrun(@sample_xctestrun, ["NetworkTests"], :module)

      refute result =~ "AppTests"
      refute result =~ "CoreTests"
      assert result =~ "NetworkTests"
    end
  end

  describe "filter_xctestrun/3 suite-level" do
    test "injects OnlyTestIdentifiers for assigned targets" do
      assigned = %{
        "AppTests" => ["LoginTest", "SignupTest"],
        "CoreTests" => ["CacheTest"]
      }

      result = PlistFilter.filter_xctestrun(@sample_xctestrun, assigned, :suite)

      assert result =~ "OnlyTestIdentifiers"
      assert result =~ "LoginTest"
      assert result =~ "SignupTest"
      assert result =~ "CacheTest"
    end

    test "targets not in map get empty OnlyTestIdentifiers" do
      assigned = %{
        "AppTests" => ["LoginTest"]
      }

      result = PlistFilter.filter_xctestrun(@sample_xctestrun, assigned, :suite)

      assert result =~ "LoginTest"

      assert result =~ "AppTests"
      assert result =~ "CoreTests"
      assert result =~ "NetworkTests"
    end

    test "preserves all test targets in output" do
      assigned = %{"AppTests" => ["LoginTest"]}
      result = PlistFilter.filter_xctestrun(@sample_xctestrun, assigned, :suite)

      assert result =~ "AppTests"
      assert result =~ "CoreTests"
      assert result =~ "NetworkTests"
    end

    test "empty assigned targets map gives empty identifiers" do
      result = PlistFilter.filter_xctestrun(@sample_xctestrun, %{}, :suite)

      assert result =~ "OnlyTestIdentifiers"
      assert result =~ "AppTests"
    end

    test "replaces existing OnlyTestIdentifiers" do
      xml_with_identifiers = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>TestConfigurations</key>
        <array>
          <dict>
            <key>Name</key>
            <string>Default</string>
            <key>TestTargets</key>
            <array>
              <dict>
                <key>BlueprintName</key>
                <string>AppTests</string>
                <key>OnlyTestIdentifiers</key>
                <array>
                  <string>OldTest</string>
                </array>
              </dict>
            </array>
          </dict>
        </array>
      </dict>
      </plist>
      """

      assigned = %{"AppTests" => ["NewTest"]}
      result = PlistFilter.filter_xctestrun(xml_with_identifiers, assigned, :suite)

      assert result =~ "NewTest"
      refute result =~ "OldTest"
    end
  end
end
