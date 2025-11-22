defmodule Tuist.Runs.TestModuleRunTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runs.TestModuleRun

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      name: "AuthenticationTests",
      test_run_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
      status: "success",
      duration: 15_000,
      test_suite_count: 3,
      test_case_count: 25,
      avg_test_case_duration: 600,
      inserted_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all required attributes" do
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.name == "AuthenticationTests"
      assert changeset.changes.test_run_id == "b23784eb-2456-4188-8c41-e8687afbdf10"
      assert changeset.changes.status == "success"
      assert changeset.changes.duration == 15_000
      assert changeset.changes.test_suite_count == 3
      assert changeset.changes.test_case_count == 25
      assert changeset.changes.avg_test_case_duration == 600
      assert changeset.changes.inserted_at == ~N[2024-01-01 12:00:00.000000]
    end

    test "accepts status 'success'" do
      attrs = Map.put(@valid_attrs, :status, "success")
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "success"
    end

    test "accepts status 'failure'" do
      attrs = Map.put(@valid_attrs, :status, "failure")
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "failure"
    end

    test "rejects invalid status string" do
      attrs = Map.put(@valid_attrs, :status, "skipped")
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects atom status" do
      attrs = Map.put(@valid_attrs, :status, :success)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects numeric status" do
      attrs = Map.put(@valid_attrs, :status, 0)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "allows nil test_suite_count" do
      attrs = Map.delete(@valid_attrs, :test_suite_count)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :test_suite_count)
    end

    test "allows nil test_case_count" do
      attrs = Map.delete(@valid_attrs, :test_case_count)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :test_case_count)
    end

    test "allows nil avg_test_case_duration" do
      attrs = Map.delete(@valid_attrs, :avg_test_case_duration)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :avg_test_case_duration)
    end

    test "allows nil inserted_at" do
      attrs = Map.delete(@valid_attrs, :inserted_at)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :inserted_at)
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires name" do
      attrs = Map.delete(@valid_attrs, :name)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires test_run_id" do
      attrs = Map.delete(@valid_attrs, :test_run_id)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_run_id
    end

    test "requires status" do
      attrs = Map.delete(@valid_attrs, :status)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).status
    end

    test "requires duration" do
      attrs = Map.delete(@valid_attrs, :duration)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).duration
    end

    test "accepts duration as zero" do
      attrs = Map.put(@valid_attrs, :duration, 0)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 0
    end

    test "accepts positive duration" do
      attrs = Map.put(@valid_attrs, :duration, 50_000)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 50_000
    end

    test "accepts test_suite_count as zero" do
      attrs = Map.put(@valid_attrs, :test_suite_count, 0)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.test_suite_count == 0
    end

    test "accepts test_case_count as zero" do
      attrs = Map.put(@valid_attrs, :test_case_count, 0)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.test_case_count == 0
    end

    test "accepts avg_test_case_duration as zero" do
      attrs = Map.put(@valid_attrs, :avg_test_case_duration, 0)
      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.avg_test_case_duration == 0
    end

    test "accepts positive test counts and averages" do
      attrs =
        @valid_attrs
        |> Map.put(:test_suite_count, 10)
        |> Map.put(:test_case_count, 100)
        |> Map.put(:avg_test_case_duration, 1500)

      changeset = TestModuleRun.create_changeset(%TestModuleRun{}, attrs)

      assert changeset.valid?
      assert changeset.changes.test_suite_count == 10
      assert changeset.changes.test_case_count == 100
      assert changeset.changes.avg_test_case_duration == 1500
    end
  end
end
