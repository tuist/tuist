defmodule Tuist.ProjectTest do
  alias Tuist.AccountsFixtures
  alias Tuist.ProjectsFixtures
  alias Tuist.Projects.Project
  use Tuist.DataCase

  test "name cannot contain dots" do
    changeset =
      Project.create_changeset(%Project{}, %{token: "token", name: "project.name", account_id: 0})

    assert changeset.valid? == false

    assert "Project name can't contain a dot. Please use a different name, such as project-name." in errors_on(
             changeset
           ).name
  end

  describe "validation of handle validity" do
    test "it fails when the handle is included in the block list" do
      # Given/When
      changeset =
        Project.create_changeset(%Project{}, %{
          name: Enum.random(Application.get_env(:tuist, :blocked_handles))
        })

      # Then
      assert changeset.valid? == false
      assert "is reserved" in errors_on(changeset).name
    end
  end

  test "it nilifies user's last visited project when the project is deleted" do
    # Given
    project = ProjectsFixtures.project_fixture()
    user = AccountsFixtures.user_fixture()
    Tuist.Accounts.update_last_visited_project(user, project.id)

    # When/Then
    assert Tuist.Repo.reload(user).last_visited_project_id == project.id
    Repo.delete!(project)
    assert Tuist.Repo.reload(user).last_visited_project_id == nil
  end

  test "visibility must be either :private or :public" do
    # When
    changeset =
      Project.create_changeset(
        %Project{},
        %{token: "token", name: "project", account_id: 0, visibility: :invalid_visibility}
      )

    # Then
    assert changeset.valid? == false
    assert "is invalid" in errors_on(changeset).visibility
  end

  test "changeset is valid when visibility is :private" do
    # When
    changeset =
      Project.create_changeset(
        %Project{},
        %{token: "token", name: "project", account_id: 0, visibility: :private}
      )

    # Then
    assert changeset.valid? == true
  end

  test "changeset is valid when visibility is :public" do
    # When
    changeset =
      Project.create_changeset(
        %Project{},
        %{token: "token", name: "project", account_id: 0, visibility: :public}
      )

    # Then
    assert changeset.valid? == true
  end
end
