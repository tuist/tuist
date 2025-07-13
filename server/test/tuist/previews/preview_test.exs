defmodule Tuist.AppBuilds.PreviewTest do
  @moduledoc false
  use TuistTestSupport.Cases.DataCase

  alias Tuist.AppBuilds.Preview

  describe "create_changeset/1" do
    test "ensures a project_id is present" do
      # Given
      preview = %Preview{}

      # When
      got = Preview.create_changeset(preview, %{})

      # Then
      assert "can't be blank" in errors_on(got).project_id
    end

    test "is valid with minimal required fields" do
      # Given
      preview = %Preview{}

      # When
      got =
        Preview.create_changeset(preview, %{
          project_id: 1,
          display_name: "My App",
          git_branch: "main",
          git_commit_sha: "abc123"
        })

      # Then
      assert got.valid?
    end

    test "accepts optional fields" do
      # Given
      preview = %Preview{}

      # When
      got =
        Preview.create_changeset(preview, %{
          project_id: 1,
          display_name: "My App",
          bundle_identifier: "com.example.app",
          version: "1.0.0",
          git_branch: "feature/new-ui",
          git_commit_sha: "def456",
          ran_by_account_id: 1
        })

      # Then
      assert got.valid?
    end

    test "is invalid when contains invalid platforms" do
      # Given
      preview = %Preview{}

      # When
      got =
        Preview.create_changeset(preview, %{
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
