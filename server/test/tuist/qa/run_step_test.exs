defmodule Tuist.QA.RunStepTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.QA.RunStep
  alias TuistTestSupport.Fixtures.QAFixtures

  describe "changeset/2" do
    setup do
      qa_run = QAFixtures.qa_run_fixture()

      valid_attrs = %{
        qa_run_id: qa_run.id,
        summary: "Successfully completed test step",
        description: "Detailed description of the test step execution",
        issues: ["Issue 1", "Issue 2"]
      }

      {:ok, qa_run: qa_run, valid_attrs: valid_attrs}
    end

    test "changeset is valid with all required attributes", %{valid_attrs: valid_attrs} do
      # When
      changeset = RunStep.changeset(%RunStep{}, valid_attrs)

      # Then
      assert changeset.valid?
    end

    test "changeset is invalid without qa_run_id", %{valid_attrs: valid_attrs} do
      # Given
      attrs = Map.delete(valid_attrs, :qa_run_id)

      # When
      changeset = RunStep.changeset(%RunStep{}, attrs)

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).qa_run_id
    end

    test "changeset is invalid without summary", %{valid_attrs: valid_attrs} do
      # Given
      attrs = Map.delete(valid_attrs, :summary)

      # When
      changeset = RunStep.changeset(%RunStep{}, attrs)

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).summary
    end

    test "changeset is invalid with non-existent qa_run_id", %{valid_attrs: valid_attrs} do
      # Given
      non_existent_id = Ecto.UUID.generate()
      attrs = Map.put(valid_attrs, :qa_run_id, non_existent_id)

      # When
      changeset = RunStep.changeset(%RunStep{}, attrs)

      # Then
      assert changeset.valid?

      # When inserting into the database
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).qa_run_id
    end

    test "changeset is invalid without description", %{valid_attrs: valid_attrs} do
      # Given
      attrs = Map.delete(valid_attrs, :description)

      # When
      changeset = RunStep.changeset(%RunStep{}, attrs)

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).description
    end

    test "changeset is invalid without issues", %{valid_attrs: valid_attrs} do
      # Given
      attrs = Map.delete(valid_attrs, :issues)

      # When
      changeset = RunStep.changeset(%RunStep{}, attrs)

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).issues
    end

    test "changeset is invalid with empty description", %{valid_attrs: valid_attrs} do
      # Given
      attrs = Map.put(valid_attrs, :description, "")

      # When
      changeset = RunStep.changeset(%RunStep{}, attrs)

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).description
    end

    test "changeset accepts empty issues array", %{valid_attrs: valid_attrs} do
      # Given
      attrs = Map.put(valid_attrs, :issues, [])

      # When
      changeset = RunStep.changeset(%RunStep{}, attrs)

      # Then
      assert changeset.valid?
      assert changeset.changes.issues == []
    end
  end
end
