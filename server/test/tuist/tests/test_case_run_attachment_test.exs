defmodule Tuist.Tests.TestCaseRunAttachmentTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Tests.TestCaseRunAttachment

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      test_case_run_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
      file_name: "crash-report.ips",
      inserted_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all attributes" do
      changeset = TestCaseRunAttachment.create_changeset(%TestCaseRunAttachment{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.test_case_run_id == "b23784eb-2456-4188-8c41-e8687afbdf10"
      assert changeset.changes.file_name == "crash-report.ips"
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = TestCaseRunAttachment.create_changeset(%TestCaseRunAttachment{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires test_case_run_id" do
      attrs = Map.delete(@valid_attrs, :test_case_run_id)
      changeset = TestCaseRunAttachment.create_changeset(%TestCaseRunAttachment{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_case_run_id
    end

    test "requires file_name" do
      attrs = Map.delete(@valid_attrs, :file_name)
      changeset = TestCaseRunAttachment.create_changeset(%TestCaseRunAttachment{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).file_name
    end
  end
end
