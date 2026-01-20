defmodule Tuist.QA.LaunchArgumentGroupTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts.Account
  alias Tuist.QA.LaunchArgumentGroup
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create_changeset/2" do
    setup do
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      {:ok, project: project}
    end

    test "valid attributes" do
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      attrs = %{
        project_id: project.id,
        name: "logged-in",
        description: "Skip login with prefilled credentials",
        value: "--email hello@tuist.dev --password 123456"
      }

      changeset = LaunchArgumentGroup.create_changeset(%LaunchArgumentGroup{}, attrs)
      assert changeset.valid?
    end

    test "requires required fields" do
      changeset = LaunchArgumentGroup.create_changeset(%LaunchArgumentGroup{}, %{})
      refute changeset.valid?

      assert %{
               project_id: ["can't be blank"],
               name: ["can't be blank"],
               value: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates name format" do
      attrs = %{
        project_id: UUIDv7.generate(),
        name: "invalid name!",
        value: "--test"
      }

      changeset = LaunchArgumentGroup.create_changeset(%LaunchArgumentGroup{}, attrs)
      refute changeset.valid?
      assert %{name: ["must contain only alphanumeric characters, hyphens, and underscores"]} = errors_on(changeset)
    end

    test "validates name length" do
      attrs = %{
        project_id: UUIDv7.generate(),
        name: String.duplicate("a", 101),
        value: "--test"
      }

      changeset = LaunchArgumentGroup.create_changeset(%LaunchArgumentGroup{}, attrs)
      refute changeset.valid?
      assert %{name: ["should be at most 100 character(s)"]} = errors_on(changeset)
    end

    test "enforces unique project_id and name", %{project: project} do
      attrs = %{
        project_id: project.id,
        name: "test-group",
        value: "--test"
      }

      assert {:ok, _} = Repo.insert(LaunchArgumentGroup.create_changeset(%LaunchArgumentGroup{}, attrs))

      {:error, changeset} = Repo.insert(LaunchArgumentGroup.create_changeset(%LaunchArgumentGroup{}, attrs))
      assert %{project_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "enforces project_id is valid" do
      attrs = %{
        project_id: UUIDv7.generate(),
        name: "test-group",
        value: "--test"
      }

      {:error, changeset} = Repo.insert(LaunchArgumentGroup.create_changeset(%LaunchArgumentGroup{}, attrs))
      assert %{project_id: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "update_changeset/2" do
    test "updates allowed fields" do
      launch_args_group = %LaunchArgumentGroup{
        project_id: UUIDv7.generate(),
        name: "original",
        value: "--original"
      }

      attrs = %{
        name: "updated",
        description: "Updated description",
        value: "--updated"
      }

      changeset = LaunchArgumentGroup.update_changeset(launch_args_group, attrs)
      assert changeset.valid?
      assert get_change(changeset, :name) == "updated"
      assert get_change(changeset, :description) == "Updated description"
      assert get_change(changeset, :value) == "--updated"
    end

    test "cannot update project_id" do
      launch_args_group = %LaunchArgumentGroup{
        project_id: UUIDv7.generate(),
        name: "test",
        value: "--test"
      }

      changeset = LaunchArgumentGroup.update_changeset(launch_args_group, %{project_id: UUIDv7.generate()})
      assert changeset.valid?
      refute get_change(changeset, :project_id)
    end
  end
end
