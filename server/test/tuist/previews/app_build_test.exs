defmodule Tuist.AppBuilds.AppBuildTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.AppBuilds.AppBuild

  describe "create_changeset/1" do
    test "ensures a preview_id is present" do
      # Given
      app_build = %AppBuild{}

      # When
      got = AppBuild.create_changeset(app_build, %{})

      # Then
      assert "can't be blank" in errors_on(got).preview_id
    end

    test "ensures type is valid" do
      # Given
      app_build = %AppBuild{}

      # When
      got = AppBuild.create_changeset(app_build, %{preview_id: 1, type: :invalid})

      # Then
      assert "is invalid" in errors_on(got).type
      refute got.valid?
    end

    test "is valid when type is app_bundle" do
      # Given
      app_build = %AppBuild{}

      # When
      got =
        AppBuild.create_changeset(app_build, %{
          preview_id: UUIDv7.generate(),
          project_id: 1,
          type: :app_bundle
        })

      # Then
      assert got.valid?
    end

    test "is valid when type is ipa" do
      # Given
      app_build = %AppBuild{}

      # When
      got =
        AppBuild.create_changeset(app_build, %{
          preview_id: UUIDv7.generate(),
          project_id: 1,
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "dev.tuist.app"
        })

      # Then
      assert got.valid?
    end

    test "is valid when type is ipa and contains valid platforms" do
      # Given
      app_build = %AppBuild{}

      # When
      got =
        AppBuild.create_changeset(app_build, %{
          preview_id: UUIDv7.generate(),
          project_id: 1,
          type: :ipa,
          display_name: "App",
          version: "1.0.0"
        })

      # Then
      assert got.valid?
    end

    test "is invalid when contains invalid platforms" do
      # Given
      app_build = %AppBuild{}

      # When
      got =
        AppBuild.create_changeset(app_build, %{
          preview_id: 1,
          project_id: 1,
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "dev.tuist.app",
          supported_platforms: [:invalid]
        })

      # Then
      refute got.valid?
    end
  end
end
