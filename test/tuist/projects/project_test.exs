defmodule Tuist.ProjectTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Projects.Project
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "name cannot contain dots" do
    changeset =
      Project.create_changeset(%Project{}, %{token: "token", name: "project.name", account_id: 0})

    assert changeset.valid? == false

    assert "Project name can't contain a dot. Please use a different name, such as project-name." in errors_on(changeset).name
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

  test "changeset is valid when vcs_provider is :github" do
    # When
    changeset =
      Project.create_changeset(
        %Project{},
        %{token: "token", name: "project", account_id: 0, vcs_provider: :github}
      )

    # Then
    assert changeset.valid? == true
  end

  test "changeset is invalid when vcs_provider is not a valid value" do
    # When
    changeset =
      Project.update_changeset(
        %Project{},
        %{token: "token", name: "project", account_id: 0, vcs_provider: :invalid_vcs_provider}
      )

    # Then
    assert changeset.valid? == false
    assert "is invalid" in errors_on(changeset).vcs_provider
  end

  describe "update_changeset/2" do
    test "it updates the default branch" do
      # Given
      project = ProjectsFixtures.project_fixture()
      new_default_branch = "new_default_branch"

      # When
      changeset = Project.update_changeset(project, %{default_branch: new_default_branch})

      # Then
      assert changeset.valid? == true
      assert changeset.changes.default_branch == new_default_branch
    end

    test "changeset is valid when vcs_provider is :github" do
      # When
      changeset =
        Project.update_changeset(
          %Project{},
          %{vcs_provider: :github}
        )

      # Then
      assert changeset.valid? == true
    end

    test "changeset is invalid when vcs_provider is not a valid value" do
      # When
      changeset =
        Project.update_changeset(
          %Project{},
          %{vcs_provider: :invalid_vcs_provider}
        )

      # Then
      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).vcs_provider
    end

    test "changeset is valid when visibility is :public" do
      # When
      changeset =
        Project.update_changeset(
          %Project{},
          %{visibility: :public}
        )

      # Then
      assert changeset.valid? == true
    end

    test "changeset is invalid when visibility is not a valid value" do
      # When
      changeset =
        Project.update_changeset(
          %Project{},
          %{visibility: :invalid_visibility}
        )

      # Then
      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).visibility
    end
  end
end
