defmodule Tuist.QA.ScreenshotTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.QA.Screenshot

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      # Given
      attrs = %{
        qa_run_id: Ecto.UUID.generate(),
        file_name: "login_screen",
        title: "Login Screen Screenshot"
      }

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      assert changeset.valid?
      assert changeset.changes.qa_run_id == attrs.qa_run_id
      assert changeset.changes.file_name == attrs.file_name
      assert changeset.changes.title == attrs.title
    end

    test "valid changeset with optional qa_run_step_id" do
      # Given
      attrs = %{
        qa_run_id: Ecto.UUID.generate(),
        qa_run_step_id: Ecto.UUID.generate(),
        file_name: "error_dialog",
        title: "Error Dialog Screenshot"
      }

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      assert changeset.valid?
      assert changeset.changes.qa_run_step_id == attrs.qa_run_step_id
    end

    test "invalid changeset without required fields" do
      # Given
      attrs = %{}

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      refute changeset.valid?
      assert {:qa_run_id, ["can't be blank"]} in errors_on(changeset)
      assert {:file_name, ["can't be blank"]} in errors_on(changeset)
      assert {:title, ["can't be blank"]} in errors_on(changeset)
    end

    test "invalid changeset without qa_run_id" do
      # Given
      attrs = %{file_name: "test_screenshot", title: "Test Screenshot"}

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      refute changeset.valid?
      assert {:qa_run_id, ["can't be blank"]} in errors_on(changeset)
    end

    test "invalid changeset without name" do
      # Given
      attrs = %{qa_run_id: Ecto.UUID.generate(), title: "Missing Name Screenshot"}

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      refute changeset.valid?
      assert {:file_name, ["can't be blank"]} in errors_on(changeset)
    end

    test "invalid changeset without title" do
      # Given
      attrs = %{qa_run_id: Ecto.UUID.generate(), file_name: "missing_title_screenshot"}

      # When
      changeset = Screenshot.changeset(%Screenshot{}, attrs)

      # Then
      refute changeset.valid?
      assert {:title, ["can't be blank"]} in errors_on(changeset)
    end
  end
end
