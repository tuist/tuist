defmodule Tuist.Runs.TestSuiteRunTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runs.TestSuiteRun

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      name: "LoginTestSuite",
      test_run_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
      test_module_run_id: "c34895fc-3567-4299-9d52-f97982cce621",
      status: "success",
      duration: 5000,
      test_case_count: 10,
      avg_test_case_duration: 500,
      inserted_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all required attributes" do
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.name == "LoginTestSuite"
      assert changeset.changes.test_run_id == "b23784eb-2456-4188-8c41-e8687afbdf10"
      assert changeset.changes.test_module_run_id == "c34895fc-3567-4299-9d52-f97982cce621"
      assert changeset.changes.status == "success"
      assert changeset.changes.duration == 5000
      assert changeset.changes.test_case_count == 10
      assert changeset.changes.avg_test_case_duration == 500
      assert changeset.changes.inserted_at == ~N[2024-01-01 12:00:00.000000]
    end

    test "accepts status 'success'" do
      attrs = Map.put(@valid_attrs, :status, "success")
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "success"
    end

    test "accepts status 'failure'" do
      attrs = Map.put(@valid_attrs, :status, "failure")
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "failure"
    end

    test "accepts status 'skipped'" do
      attrs = Map.put(@valid_attrs, :status, "skipped")
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "skipped"
    end

    test "rejects invalid status string" do
      attrs = Map.put(@valid_attrs, :status, "unknown")
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects atom status" do
      attrs = Map.put(@valid_attrs, :status, :success)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects numeric status" do
      attrs = Map.put(@valid_attrs, :status, 0)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "allows nil test_case_count" do
      attrs = Map.delete(@valid_attrs, :test_case_count)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :test_case_count)
    end

    test "allows nil avg_test_case_duration" do
      attrs = Map.delete(@valid_attrs, :avg_test_case_duration)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :avg_test_case_duration)
    end

    test "allows nil inserted_at" do
      attrs = Map.delete(@valid_attrs, :inserted_at)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :inserted_at)
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires name" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires test_run_id" do
      attrs = Map.delete(@valid_attrs, :test_run_id)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_run_id
    end

    test "requires test_module_run_id" do
      attrs = Map.delete(@valid_attrs, :test_module_run_id)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_module_run_id
    end

    test "requires status" do
      attrs = Map.delete(@valid_attrs, :status)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).status
    end

    test "requires duration" do
      attrs = Map.delete(@valid_attrs, :duration)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).duration
    end

    test "accepts duration as zero" do
      attrs = Map.put(@valid_attrs, :duration, 0)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 0
    end

    test "accepts positive duration" do
      attrs = Map.put(@valid_attrs, :duration, 10_000)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 10_000
    end

    test "accepts test_case_count as zero" do
      attrs = Map.put(@valid_attrs, :test_case_count, 0)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.test_case_count == 0
    end

    test "accepts positive test_case_count" do
      attrs = Map.put(@valid_attrs, :test_case_count, 50)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.test_case_count == 50
    end

    test "accepts avg_test_case_duration as zero" do
      attrs = Map.put(@valid_attrs, :avg_test_case_duration, 0)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.avg_test_case_duration == 0
    end

    test "accepts positive avg_test_case_duration" do
      attrs = Map.put(@valid_attrs, :avg_test_case_duration, 1500)
      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.avg_test_case_duration == 1500
    end

    test "accepts positive test_case_count and avg_test_case_duration together" do
      attrs =
        @valid_attrs
        |> Map.put(:test_case_count, 25)
        |> Map.put(:avg_test_case_duration, 800)

      changeset = TestSuiteRun.create_changeset(%TestSuiteRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.test_case_count == 25
      assert changeset.changes.avg_test_case_duration == 800
    end
  end
end
