defmodule Tuist.Previews.PreviewTest do
  alias Tuist.Previews.Preview
  use Tuist.DataCase

  describe "create_changeset/1" do
    test "ensures a project_id is present" do
      # Given
      preview = %Preview{}

      # When
      got = Preview.create_changeset(preview, %{})

      # Then
      assert "can't be blank" in errors_on(got).project_id
    end

    test "ensures type is valid" do
      # Given
      preview = %Preview{}

      # When
      got = Preview.create_changeset(preview, %{project_id: 1, type: :invalid})

      # Then
      assert "is invalid" in errors_on(got).type
      refute got.valid?
    end

    test "is valid when type is app_bundle" do
      # Given
      preview = %Preview{}

      # When
      got = Preview.create_changeset(preview, %{project_id: 1, type: :app_bundle})

      # Then
      assert got.valid?
    end

    test "is valid when type is ipa" do
      # Given
      preview = %Preview{}

      # When
      got =
        Preview.create_changeset(preview, %{
          project_id: 1,
          type: :ipa,
          display_name: "App",
          version: "1.0.0",
          bundle_identifier: "com.tuist.app"
        })

      # Then
      assert got.valid?
    end
  end
end
