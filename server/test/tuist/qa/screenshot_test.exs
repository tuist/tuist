defmodule Tuist.QA.ScreenshotTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.QA.Screenshot

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      # Given
      attrs = %{
        qa_run_id: UUIDv7.generate()
      }

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      assert changeset.valid?
    end

    test "valid changeset with optional qa_step_id" do
      # Given
      attrs = %{
        qa_run_id: UUIDv7.generate(),
        qa_step_id: UUIDv7.generate()
      }

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      assert changeset.valid?
    end

    test "invalid changeset without required fields" do
      # Given
      attrs = %{}

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      refute changeset.valid?
      assert {:qa_run_id, ["can't be blank"]} in errors_on(changeset)
    end

    test "invalid changeset without qa_run_id" do
      # Given
      attrs = %{}

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      refute changeset.valid?
      assert {:qa_run_id, ["can't be blank"]} in errors_on(changeset)
    end
  end
end
