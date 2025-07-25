defmodule Tuist.QA.RunStepTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.QA.RunStep
  alias TuistTestSupport.Fixtures.QAFixtures

  describe "changeset/2" do
    test "changeset is valid with valid attributes" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      # When
      changeset =
        RunStep.changeset(%RunStep{}, %{
          qa_run_id: qa_run.id,
          summary: "Successfully completed test step"
        })

      # Then
      assert changeset.valid?
    end

    test "changeset is invalid without qa_run_id" do
      # When
      changeset =
        RunStep.changeset(%RunStep{}, %{
          summary: "Successfully completed test step"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).qa_run_id
    end

    test "changeset is invalid without summary" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      # When
      changeset =
        RunStep.changeset(%RunStep{}, %{
          qa_run_id: qa_run.id
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).summary
    end

    test "changeset is invalid with empty summary" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      # When
      changeset =
        RunStep.changeset(%RunStep{}, %{
          qa_run_id: qa_run.id,
          summary: ""
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).summary
    end

    test "changeset is invalid with non-existent qa_run_id" do
      # Given
      non_existent_id = Ecto.UUID.generate()

      # When
      changeset =
        RunStep.changeset(%RunStep{}, %{
          qa_run_id: non_existent_id,
          summary: "Test summary"
        })

      # Then
      assert changeset.valid?

      # When inserting into the database
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).qa_run_id
    end

    test "changeset accepts long summary text" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      long_summary = String.duplicate("This is a very long summary. ", 100)

      # When
      changeset =
        RunStep.changeset(%RunStep{}, %{
          qa_run_id: qa_run.id,
          summary: long_summary
        })

      # Then
      assert changeset.valid?
      assert changeset.changes.summary == long_summary
    end
  end
end