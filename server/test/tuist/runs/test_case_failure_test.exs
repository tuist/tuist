defmodule Tuist.Runs.TestCaseFailureTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runs.TestCaseFailure

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      test_case_run_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
      message: "Expected true but got false",
      path: "/path/to/test/file.swift",
      line_number: 42,
      issue_type: "assertion_failure",
      inserted_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all required attributes" do
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.test_case_run_id == "b23784eb-2456-4188-8c41-e8687afbdf10"
      assert changeset.changes.message == "Expected true but got false"
      assert changeset.changes.path == "/path/to/test/file.swift"
      assert changeset.changes.line_number == 42
      assert changeset.changes.issue_type == "assertion_failure"
      assert changeset.changes.inserted_at == ~N[2024-01-01 12:00:00.000000]
    end

    test "accepts issue_type 'assertion_failure'" do
      attrs = Map.put(@valid_attrs, :issue_type, "assertion_failure")
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      assert changeset.valid?
      assert changeset.changes.issue_type == "assertion_failure"
    end

    test "accepts issue_type 'error_thrown'" do
      attrs = Map.put(@valid_attrs, :issue_type, "error_thrown")
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      assert changeset.valid?
      assert changeset.changes.issue_type == "error_thrown"
    end

    test "accepts issue_type 'unknown'" do
      attrs = Map.put(@valid_attrs, :issue_type, "unknown")
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      assert changeset.valid?
      assert changeset.changes.issue_type == "unknown"
    end

    test "defaults to 'unknown' when issue_type is not provided" do
      attrs = Map.delete(@valid_attrs, :issue_type)
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      assert changeset.valid?
      assert changeset.changes.issue_type == "unknown"
    end

    test "rejects invalid issue_type" do
      attrs = Map.put(@valid_attrs, :issue_type, "invalid_type")
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).issue_type
    end

    test "allows nil message" do
      attrs = Map.delete(@valid_attrs, :message)
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :message)
    end

    test "allows nil path" do
      attrs = Map.delete(@valid_attrs, :path)
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :path)
    end

    test "allows nil inserted_at" do
      attrs = Map.delete(@valid_attrs, :inserted_at)
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :inserted_at)
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires test_case_run_id" do
      attrs = Map.delete(@valid_attrs, :test_case_run_id)
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_case_run_id
    end

    test "requires line_number" do
      attrs = Map.delete(@valid_attrs, :line_number)
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).line_number
    end

    test "accepts line_number as positive integer" do
      attrs = Map.put(@valid_attrs, :line_number, 100)
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      assert changeset.valid?
      assert changeset.changes.line_number == 100
    end

    test "accepts line_number as zero" do
      attrs = Map.put(@valid_attrs, :line_number, 0)
      changeset = TestCaseFailure.create_changeset(%TestCaseFailure{}, attrs)

      assert changeset.valid?
      assert changeset.changes.line_number == 0
    end
  end
end
