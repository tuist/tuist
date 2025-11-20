defmodule Tuist.Runs.TestTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runs.Test

  describe "create_changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      duration: 1500,
      macos_version: "14.0",
      xcode_version: "15.0",
      is_ci: true,
      project_id: 123,
      account_id: 456,
      status: :success,
      ran_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all required attributes" do
      changeset = Test.create_changeset(%Test{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.duration == 1500
      assert changeset.changes.macos_version == "14.0"
      assert changeset.changes.xcode_version == "15.0"
      assert changeset.changes.is_ci == true
      assert changeset.changes.project_id == 123
      assert changeset.changes.account_id == 456
      assert changeset.changes.status == 0
      assert changeset.changes.ran_at == ~N[2024-01-01 12:00:00.000000]
    end

    test "maps :success status to 0" do
      attrs = Map.put(@valid_attrs, :status, :success)
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == 0
    end

    test "maps :failure status to 1" do
      attrs = Map.put(@valid_attrs, :status, :failure)
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == 1
    end

    test "accepts numeric status 0" do
      attrs = Map.put(@valid_attrs, :status, 0)
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == 0
    end

    test "accepts numeric status 1" do
      attrs = Map.put(@valid_attrs, :status, 1)
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == 1
    end

    test "rejects invalid status values" do
      attrs = Map.put(@valid_attrs, :status, 2)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects invalid atom status" do
      attrs = Map.put(@valid_attrs, :status, :unknown)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "includes optional model_identifier" do
      attrs = Map.put(@valid_attrs, :model_identifier, "MacBookPro18,3")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.model_identifier == "MacBookPro18,3"
    end

    test "includes optional scheme" do
      attrs = Map.put(@valid_attrs, :scheme, "MyAppScheme")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.scheme == "MyAppScheme"
    end

    test "includes optional git_branch" do
      attrs = Map.put(@valid_attrs, :git_branch, "main")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.git_branch == "main"
    end

    test "includes optional git_commit_sha" do
      attrs = Map.put(@valid_attrs, :git_commit_sha, "abc123def456")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.git_commit_sha == "abc123def456"
    end

    test "includes optional git_ref" do
      attrs = Map.put(@valid_attrs, :git_ref, "refs/heads/main")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.git_ref == "refs/heads/main"
    end

    test "includes optional inserted_at" do
      inserted_at = ~N[2024-01-01 13:00:00.000000]
      attrs = Map.put(@valid_attrs, :inserted_at, inserted_at)
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.inserted_at == inserted_at
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires duration" do
      attrs = Map.delete(@valid_attrs, :duration)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).duration
    end

    test "requires macos_version" do
      attrs = Map.delete(@valid_attrs, :macos_version)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).macos_version
    end

    test "requires xcode_version" do
      attrs = Map.delete(@valid_attrs, :xcode_version)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).xcode_version
    end

    test "requires is_ci" do
      attrs = Map.delete(@valid_attrs, :is_ci)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).is_ci
    end

    test "requires project_id" do
      attrs = Map.delete(@valid_attrs, :project_id)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).project_id
    end

    test "requires account_id" do
      attrs = Map.delete(@valid_attrs, :account_id)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).account_id
    end

    test "requires status" do
      attrs = Map.delete(@valid_attrs, :status)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).status
    end

    test "requires ran_at" do
      attrs = Map.delete(@valid_attrs, :ran_at)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).ran_at
    end

    test "accepts is_ci as false" do
      attrs = Map.put(@valid_attrs, :is_ci, false)
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.is_ci == false
    end
  end
end
