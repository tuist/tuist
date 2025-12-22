defmodule Tuist.QA.RecordingTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.QA.Recording
  alias TuistTestSupport.Fixtures.QAFixtures

  describe "create_changeset/2" do
    test "is valid with valid attributes" do
      # Given
      run = QAFixtures.qa_run_fixture()
      started_at = DateTime.utc_now()

      # When
      changeset =
        Recording.create_changeset(%Recording{}, %{
          qa_run_id: run.id,
          started_at: started_at,
          duration: 1500
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid without qa_run_id" do
      # Given
      started_at = DateTime.utc_now()

      # When
      changeset =
        Recording.create_changeset(%Recording{}, %{
          started_at: started_at,
          duration: 1500
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).qa_run_id
    end

    test "is invalid without started_at" do
      # Given
      run = QAFixtures.qa_run_fixture()

      # When
      changeset =
        Recording.create_changeset(%Recording{}, %{
          qa_run_id: run.id,
          duration: 1500
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).started_at
    end

    test "is invalid without duration" do
      # Given
      run = QAFixtures.qa_run_fixture()
      started_at = DateTime.utc_now()

      # When
      changeset =
        Recording.create_changeset(%Recording{}, %{
          qa_run_id: run.id,
          started_at: started_at
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).duration
    end

    test "is invalid with non-existent qa_run_id" do
      # Given
      non_existent_id = UUIDv7.generate()
      started_at = DateTime.utc_now()

      # When
      changeset =
        Recording.create_changeset(%Recording{}, %{
          qa_run_id: non_existent_id,
          started_at: started_at,
          duration: 1500
        })

      # Then
      assert changeset.valid?

      # When
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).qa_run_id
    end
  end
end
