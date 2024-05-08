defmodule TuistCloud.ProjectTest do
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
end
