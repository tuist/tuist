defmodule Tuist.QA.LaunchArgumentsGroupTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts.Account
  alias Tuist.QA.LaunchArgumentsGroup
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create_changeset/2" do
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

      changeset = LaunchArgumentsGroup.create_changeset(%LaunchArgumentsGroup{}, attrs)
      assert changeset.valid?
    end

    test "requires required fields" do
      changeset = LaunchArgumentsGroup.create_changeset(%LaunchArgumentsGroup{}, %{})
      refute changeset.valid?

      assert %{
               project_id: ["can't be blank"],
               name: ["can't be blank"],
               value: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates name format" do
      attrs = %{
        project_id: Ecto.UUID.generate(),
        name: "invalid name!",
        value: "--test"
      }

      changeset = LaunchArgumentsGroup.create_changeset(%LaunchArgumentsGroup{}, attrs)
      refute changeset.valid?
      assert %{name: ["must contain only alphanumeric characters, hyphens, and underscores"]} = errors_on(changeset)
    end

    test "validates name length" do
      attrs = %{
        project_id: Ecto.UUID.generate(),
        name: String.duplicate("a", 101),
        value: "--test"
      }

      changeset = LaunchArgumentsGroup.create_changeset(%LaunchArgumentsGroup{}, attrs)
      refute changeset.valid?
      assert %{name: ["should be at most 100 character(s)"]} = errors_on(changeset)
    end
  end

  describe "update_changeset/2" do
    test "updates allowed fields" do
      launch_args_group = %LaunchArgumentsGroup{
        project_id: Ecto.UUID.generate(),
        name: "original",
        value: "--original"
      }

      attrs = %{
        name: "updated",
        description: "Updated description",
        value: "--updated"
      }

      changeset = LaunchArgumentsGroup.update_changeset(launch_args_group, attrs)
      assert changeset.valid?
      assert get_change(changeset, :name) == "updated"
      assert get_change(changeset, :description) == "Updated description"
      assert get_change(changeset, :value) == "--updated"
    end

    test "cannot update project_id" do
      launch_args_group = %LaunchArgumentsGroup{
        project_id: Ecto.UUID.generate(),
        name: "test",
        value: "--test"
      }

      changeset = LaunchArgumentsGroup.update_changeset(launch_args_group, %{project_id: Ecto.UUID.generate()})
      assert changeset.valid?
      refute get_change(changeset, :project_id)
    end
  end

  describe "database constraints" do
    setup do
      organization = AccountsFixtures.organization_fixture()
      account = Repo.get_by!(Account, organization_id: organization.id)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      {:ok, project: project}
    end

    test "enforces unique constraint on project_id and name", %{project: project} do
      attrs = %{
        project_id: project.id,
        name: "test-group",
        value: "--test"
      }

      assert {:ok, _} = Repo.insert(LaunchArgumentsGroup.create_changeset(%LaunchArgumentsGroup{}, attrs))

      {:error, changeset} = Repo.insert(LaunchArgumentsGroup.create_changeset(%LaunchArgumentsGroup{}, attrs))
      assert %{project_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "enforces foreign key constraint on project_id" do
      attrs = %{
        project_id: Ecto.UUID.generate(),
        name: "test-group",
        value: "--test"
      }

      {:error, changeset} = Repo.insert(LaunchArgumentsGroup.create_changeset(%LaunchArgumentsGroup{}, attrs))
      assert %{project_id: ["is invalid"]} = errors_on(changeset)
    end
  end
end
