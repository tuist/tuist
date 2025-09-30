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

  test "name cannot contain spaces" do
    changeset =
      Project.create_changeset(%Project{}, %{token: "token", name: "my project", account_id: 0})

    assert changeset.valid? == false

    assert "must contain only alphanumeric characters, hyphens, and underscores" in errors_on(changeset).name
  end

  test "name cannot contain other invalid characters" do
    changeset =
      Project.create_changeset(%Project{}, %{token: "token", name: "project@name", account_id: 0})

    assert changeset.valid? == false

    assert "must contain only alphanumeric characters, hyphens, and underscores" in errors_on(changeset).name
  end

  test "name can contain underscores" do
    changeset =
      Project.create_changeset(%Project{}, %{token: "token", name: "project_name", account_id: 0})

    assert changeset.valid? == true
  end

  test "name must be at least 1 character long" do
    changeset =
      Project.create_changeset(%Project{}, %{token: "token", name: "", account_id: 0})

    assert changeset.valid? == false
    assert "can't be blank" in errors_on(changeset).name
  end

  test "name cannot exceed 32 characters" do
    changeset =
      Project.create_changeset(%Project{}, %{token: "token", name: String.duplicate("a", 33), account_id: 0})

    assert changeset.valid? == false
    assert "should be at most 32 character(s)" in errors_on(changeset).name
  end

  test "name with exactly 32 characters is valid" do
    changeset =
      Project.create_changeset(%Project{}, %{token: "token", name: String.duplicate("a", 32), account_id: 0})

    assert changeset.valid? == true
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

    test "update changeset is valid when default_previews_visibility is :private" do
      # When
      changeset =
        Project.update_changeset(
          %Project{},
          %{default_previews_visibility: :private}
        )

      # Then
      assert changeset.valid? == true
    end

    test "update changeset is valid when default_previews_visibility is :public" do
      # When
      changeset =
        Project.update_changeset(
          %Project{},
          %{default_previews_visibility: :public}
        )

      # Then
      assert changeset.valid? == true
    end

    test "update changeset is invalid when default_previews_visibility is not a valid value" do
      # When
      changeset =
        Project.update_changeset(
          %Project{},
          %{default_previews_visibility: :invalid_visibility}
        )

      # Then
      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).default_previews_visibility
    end

    test "name cannot contain dots on update" do
      changeset =
        Project.update_changeset(%Project{}, %{name: "project.name"})

      assert changeset.valid? == false

      assert "Project name can't contain a dot. Please use a different name, such as project-name." in errors_on(
               changeset
             ).name
    end

    test "name cannot contain spaces on update" do
      changeset =
        Project.update_changeset(%Project{}, %{name: "my project"})

      assert changeset.valid? == false
      assert "must contain only alphanumeric characters, hyphens, and underscores" in errors_on(changeset).name
    end

    test "name cannot contain invalid characters on update" do
      changeset =
        Project.update_changeset(%Project{}, %{name: "project@name"})

      assert changeset.valid? == false
      assert "must contain only alphanumeric characters, hyphens, and underscores" in errors_on(changeset).name
    end

    test "name can contain underscores on update" do
      changeset =
        Project.update_changeset(%Project{}, %{name: "project_name"})

      assert changeset.valid? == true
    end

    test "name cannot exceed 32 characters on update" do
      changeset =
        Project.update_changeset(%Project{}, %{name: String.duplicate("a", 33)})

      assert changeset.valid? == false
      assert "should be at most 32 character(s)" in errors_on(changeset).name
    end

    test "name with exactly 32 characters is valid on update" do
      changeset =
        Project.update_changeset(%Project{}, %{name: String.duplicate("a", 32)})

      assert changeset.valid? == true
    end

    test "blocked handles are not allowed on update" do
      changeset =
        Project.update_changeset(%Project{}, %{
          name: Enum.random(Application.get_env(:tuist, :blocked_handles))
        })

      assert changeset.valid? == false
      assert "is reserved" in errors_on(changeset).name
    end

    test "name is downcased on update" do
      changeset =
        Project.update_changeset(%Project{}, %{name: "PROJECT_NAME"})

      assert changeset.valid? == true
      assert changeset.changes.name == "project_name"
    end
  end
end
