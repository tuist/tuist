defmodule Tuist.Tests.CrashReportTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Tests.CrashReport

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      exception_type: "EXC_CRASH",
      signal: "SIGABRT",
      exception_subtype: "KERN_INVALID_ADDRESS",
      triggered_thread_frames: "0  libswiftCore.dylib  _assertionFailure + 156",
      test_case_run_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
      test_case_run_attachment_id: "c34895fc-3567-4299-9d52-f9798b0cef21",
      inserted_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all attributes" do
      changeset = CrashReport.create_changeset(%CrashReport{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.exception_type == "EXC_CRASH"
      assert changeset.changes.signal == "SIGABRT"
      assert changeset.changes.exception_subtype == "KERN_INVALID_ADDRESS"
      assert changeset.changes.test_case_run_id == "b23784eb-2456-4188-8c41-e8687afbdf10"
      assert changeset.changes.test_case_run_attachment_id == "c34895fc-3567-4299-9d52-f9798b0cef21"
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = CrashReport.create_changeset(%CrashReport{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires test_case_run_id" do
      attrs = Map.delete(@valid_attrs, :test_case_run_id)
      changeset = CrashReport.create_changeset(%CrashReport{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_case_run_id
    end

    test "requires test_case_run_attachment_id" do
      attrs = Map.delete(@valid_attrs, :test_case_run_attachment_id)
      changeset = CrashReport.create_changeset(%CrashReport{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_case_run_attachment_id
    end

    test "allows optional fields to be omitted" do
      attrs = %{
        id: "a12673da-1345-4077-bb30-d7576feace09",
        test_case_run_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
        test_case_run_attachment_id: "c34895fc-3567-4299-9d52-f9798b0cef21"
      }

      changeset = CrashReport.create_changeset(%CrashReport{}, attrs)

      assert changeset.valid?
    end
  end
end
