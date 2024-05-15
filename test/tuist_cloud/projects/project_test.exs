defmodule TuistCloud.ProjectTest do
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.Projects.Project
  use TuistCloud.DataCase

  test "name cannot contain dots" do
    changeset =
      Project.create_changeset(%Project{}, %{token: "token", name: "project.name", account_id: 0})

    assert changeset.valid? == false

    assert "Project name can't contain a dot. Please use a different name, such as project-name." in errors_on(
             changeset
           ).name
  end

  test "it nilifies user's last visited project when the project is deleted" do
    # Given
    project = ProjectsFixtures.project_fixture()
    user = AccountsFixtures.user_fixture()
    TuistCloud.Accounts.update_last_visited_project(user, project.id)

    # When/Then
    assert TuistCloud.Repo.reload(user).last_visited_project_id == project.id
    Repo.delete!(project)
    assert TuistCloud.Repo.reload(user).last_visited_project_id == nil
  end
end
