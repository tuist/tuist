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
      status: "success",
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
      assert changeset.changes.status == "success"
      assert changeset.changes.ran_at == ~N[2024-01-01 12:00:00.000000]
    end

    test "accepts string status 'success'" do
      attrs = Map.put(@valid_attrs, :status, "success")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "success"
    end

    test "accepts string status 'failure'" do
      attrs = Map.put(@valid_attrs, :status, "failure")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "failure"
    end

    test "rejects invalid status string" do
      attrs = Map.put(@valid_attrs, :status, "unknown")
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects atom status" do
      attrs = Map.put(@valid_attrs, :status, :success)
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects numeric status" do
      attrs = Map.put(@valid_attrs, :status, 0)
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

    test "includes optional ci_run_id" do
      attrs = Map.put(@valid_attrs, :ci_run_id, "19683527895")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.ci_run_id == "19683527895"
    end

    test "includes optional ci_project_handle" do
      attrs = Map.put(@valid_attrs, :ci_project_handle, "tuist/tuist")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.ci_project_handle == "tuist/tuist"
    end

    test "includes optional ci_host" do
      attrs = Map.put(@valid_attrs, :ci_host, "gitlab.example.com")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.ci_host == "gitlab.example.com"
    end

    test "accepts ci_provider 'github'" do
      attrs = Map.put(@valid_attrs, :ci_provider, "github")
      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.ci_provider == "github"
    end

    test "rejects invalid ci_provider" do
      attrs = Map.put(@valid_attrs, :ci_provider, "invalid_provider")
      changeset = Test.create_changeset(%Test{}, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).ci_provider
    end

    test "accepts all CI fields together" do
      attrs =
        @valid_attrs
        |> Map.put(:ci_run_id, "19683527895")
        |> Map.put(:ci_project_handle, "tuist/tuist")
        |> Map.put(:ci_host, "github.com")
        |> Map.put(:ci_provider, "github")

      changeset = Test.create_changeset(%Test{}, attrs)

      assert changeset.valid?
      assert changeset.changes.ci_run_id == "19683527895"
      assert changeset.changes.ci_project_handle == "tuist/tuist"
      assert changeset.changes.ci_host == "github.com"
      assert changeset.changes.ci_provider == "github"
    end
  end
end
