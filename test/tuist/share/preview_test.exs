defmodule Tuist.Projects.PreviewTest do
  alias Tuist.Projects.Preview
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

    test "is valid when project_id is present" do
      # Given
      preview = %Preview{}

      # When
      got = Preview.create_changeset(preview, %{project_id: 1})

      # Then
      assert got.valid?
    end
  end
end
