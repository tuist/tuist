defmodule Tuist.Tests.TestCaseRunRepetitionTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Tests.TestCaseRunRepetition

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      test_case_run_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
      repetition_number: 1,
      name: "testLoginSuccess",
      status: "success",
      duration: 1500,
      inserted_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all required attributes" do
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.test_case_run_id == "b23784eb-2456-4188-8c41-e8687afbdf10"
      assert changeset.changes.repetition_number == 1
      assert changeset.changes.name == "testLoginSuccess"
      assert changeset.changes.status == "success"
      assert changeset.changes.duration == 1500
      assert changeset.changes.inserted_at == ~N[2024-01-01 12:00:00.000000]
    end

    test "accepts status 'success'" do
      attrs = Map.put(@valid_attrs, :status, "success")
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "success"
    end

    test "accepts status 'failure'" do
      attrs = Map.put(@valid_attrs, :status, "failure")
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "failure"
    end

    test "rejects status 'skipped'" do
      attrs = Map.put(@valid_attrs, :status, "skipped")
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects invalid status string" do
      attrs = Map.put(@valid_attrs, :status, "unknown")
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects atom status" do
      attrs = Map.put(@valid_attrs, :status, :success)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects numeric status" do
      attrs = Map.put(@valid_attrs, :status, 0)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires test_case_run_id" do
      attrs = Map.delete(@valid_attrs, :test_case_run_id)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_case_run_id
    end

    test "requires repetition_number" do
      attrs = Map.delete(@valid_attrs, :repetition_number)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).repetition_number
    end

    test "requires name" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires status" do
      attrs = Map.delete(@valid_attrs, :status)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).status
    end

    test "allows nil duration" do
      attrs = Map.delete(@valid_attrs, :duration)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :duration)
    end

    test "allows nil inserted_at" do
      attrs = Map.delete(@valid_attrs, :inserted_at)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :inserted_at)
    end

    test "accepts duration as zero" do
      attrs = Map.put(@valid_attrs, :duration, 0)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 0
    end

    test "accepts positive duration" do
      attrs = Map.put(@valid_attrs, :duration, 5000)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 5000
    end

    test "accepts repetition_number as zero" do
      attrs = Map.put(@valid_attrs, :repetition_number, 0)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      assert changeset.valid?
      assert changeset.changes.repetition_number == 0
    end

    test "accepts higher repetition_number" do
      attrs = Map.put(@valid_attrs, :repetition_number, 5)
      changeset = TestCaseRunRepetition.create_changeset(%TestCaseRunRepetition{}, attrs)

      assert changeset.valid?
      assert changeset.changes.repetition_number == 5
    end
  end
end
