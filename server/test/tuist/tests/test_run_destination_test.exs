defmodule Tuist.Tests.TestRunDestinationTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Tests.TestRunDestination

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      test_run_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
      name: "iPhone Air",
      platform: "iOS Simulator",
      os_version: "26.4",
      inserted_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all required attributes" do
      changeset = TestRunDestination.create_changeset(%TestRunDestination{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.test_run_id == "b23784eb-2456-4188-8c41-e8687afbdf10"
      assert changeset.changes.name == "iPhone Air"
      assert changeset.changes.platform == "iOS Simulator"
      assert changeset.changes.os_version == "26.4"
      assert changeset.changes.inserted_at == ~N[2024-01-01 12:00:00.000000]
    end

    test "requires id" do
      changeset =
        TestRunDestination.create_changeset(%TestRunDestination{}, Map.delete(@valid_attrs, :id))

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires test_run_id" do
      changeset =
        TestRunDestination.create_changeset(
          %TestRunDestination{},
          Map.delete(@valid_attrs, :test_run_id)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_run_id
    end

    test "requires name" do
      changeset =
        TestRunDestination.create_changeset(
          %TestRunDestination{},
          Map.delete(@valid_attrs, :name)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires platform" do
      changeset =
        TestRunDestination.create_changeset(
          %TestRunDestination{},
          Map.delete(@valid_attrs, :platform)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).platform
    end

    test "requires os_version" do
      changeset =
        TestRunDestination.create_changeset(
          %TestRunDestination{},
          Map.delete(@valid_attrs, :os_version)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).os_version
    end

    test "allows nil inserted_at" do
      changeset =
        TestRunDestination.create_changeset(
          %TestRunDestination{},
          Map.delete(@valid_attrs, :inserted_at)
        )

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :inserted_at)
    end
  end

  describe "normalize_platform/1" do
    test "maps known real-device platforms to snake-case strings" do
      assert TestRunDestination.normalize_platform("macOS") == "macos"
      assert TestRunDestination.normalize_platform("iOS") == "ios"
      assert TestRunDestination.normalize_platform("tvOS") == "tvos"
      assert TestRunDestination.normalize_platform("watchOS") == "watchos"
      assert TestRunDestination.normalize_platform("visionOS") == "visionos"
    end

    test "maps known simulator platforms to snake-case strings" do
      assert TestRunDestination.normalize_platform("iOS Simulator") == "ios_simulator"
      assert TestRunDestination.normalize_platform("tvOS Simulator") == "tvos_simulator"
      assert TestRunDestination.normalize_platform("watchOS Simulator") == "watchos_simulator"
      assert TestRunDestination.normalize_platform("visionOS Simulator") == "visionos_simulator"
    end

    test "folds iPadOS onto the iOS family" do
      assert TestRunDestination.normalize_platform("iPadOS") == "ios"
      assert TestRunDestination.normalize_platform("iPadOS Simulator") == "ios_simulator"
    end

    test "returns \"unknown\" for unrecognised platforms" do
      assert TestRunDestination.normalize_platform("Linux") == "unknown"
      assert TestRunDestination.normalize_platform(nil) == "unknown"
    end
  end

  describe "humanize_platform/1" do
    test "reverses the normalised form back to the xcresult-style display string" do
      assert TestRunDestination.humanize_platform("macos") == "macOS"
      assert TestRunDestination.humanize_platform("ios") == "iOS"
      assert TestRunDestination.humanize_platform("ios_simulator") == "iOS Simulator"
      assert TestRunDestination.humanize_platform("tvos_simulator") == "tvOS Simulator"
      assert TestRunDestination.humanize_platform("watchos_simulator") == "watchOS Simulator"
      assert TestRunDestination.humanize_platform("visionos_simulator") == "visionOS Simulator"
    end

    test "accepts a struct and delegates on its platform" do
      destination = %TestRunDestination{platform: "ios_simulator"}
      assert TestRunDestination.humanize_platform(destination) == "iOS Simulator"
    end

    test "passes unrecognised binary platforms through unchanged" do
      assert TestRunDestination.humanize_platform("freebsd") == "freebsd"
    end

    test "returns an empty string for nil platforms" do
      assert TestRunDestination.humanize_platform(nil) == ""
      assert TestRunDestination.humanize_platform(%TestRunDestination{platform: nil}) == ""
    end
  end
end
