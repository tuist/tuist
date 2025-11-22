defmodule Tuist.Runs.TestCaseRunTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runs.TestCaseRun

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      name: "testLoginSuccess",
      test_run_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
      test_module_run_id: "c34895fc-3567-4299-9d52-f97982cce621",
      test_suite_run_id: "d459a6ad-4678-4300-ae63-a08012345632",
      status: "success",
      duration: 1500,
      module_name: "AuthenticationTests",
      suite_name: "LoginTestSuite",
      inserted_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all required attributes" do
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.name == "testLoginSuccess"
      assert changeset.changes.test_run_id == "b23784eb-2456-4188-8c41-e8687afbdf10"
      assert changeset.changes.test_module_run_id == "c34895fc-3567-4299-9d52-f97982cce621"
      assert changeset.changes.test_suite_run_id == "d459a6ad-4678-4300-ae63-a08012345632"
      assert changeset.changes.status == "success"
      assert changeset.changes.duration == 1500
      assert changeset.changes.module_name == "AuthenticationTests"
      assert changeset.changes.suite_name == "LoginTestSuite"
      assert changeset.changes.inserted_at == ~N[2024-01-01 12:00:00.000000]
    end

    test "accepts status 'success'" do
      attrs = Map.put(@valid_attrs, :status, "success")
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "success"
    end

    test "accepts status 'failure'" do
      attrs = Map.put(@valid_attrs, :status, "failure")
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "failure"
    end

    test "accepts status 'skipped'" do
      attrs = Map.put(@valid_attrs, :status, "skipped")
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "skipped"
    end

    test "rejects invalid status string" do
      attrs = Map.put(@valid_attrs, :status, "unknown")
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects atom status" do
      attrs = Map.put(@valid_attrs, :status, :success)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects numeric status" do
      attrs = Map.put(@valid_attrs, :status, 0)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "allows nil test_suite_run_id" do
      attrs = Map.delete(@valid_attrs, :test_suite_run_id)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :test_suite_run_id)
    end

    test "allows nil inserted_at" do
      attrs = Map.delete(@valid_attrs, :inserted_at)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :inserted_at)
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires name" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires test_run_id" do
      attrs = Map.delete(@valid_attrs, :test_run_id)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_run_id
    end

    test "requires test_module_run_id" do
      attrs = Map.delete(@valid_attrs, :test_module_run_id)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_module_run_id
    end

    test "requires status" do
      attrs = Map.delete(@valid_attrs, :status)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).status
    end

    test "requires duration" do
      attrs = Map.delete(@valid_attrs, :duration)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).duration
    end

    test "requires module_name" do
      attrs = Map.delete(@valid_attrs, :module_name)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).module_name
    end

    test "requires suite_name" do
      attrs = Map.delete(@valid_attrs, :suite_name)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).suite_name
    end

    test "accepts duration as zero" do
      attrs = Map.put(@valid_attrs, :duration, 0)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 0
    end

    test "accepts positive duration" do
      attrs = Map.put(@valid_attrs, :duration, 5000)
      changeset = TestCaseRun.create_changeset(%TestCaseRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 5000
    end
  end
end
