defmodule Atlas.Engineering.ProjectsTest do
  use Atlas.DataCase, async: true

  alias Atlas.Engineering.Projects

  describe "list_projects/0" do
    test "is empty by default" do
      assert Projects.list_projects() == []
    end
  end

  describe "create_project/1" do
    test "inserts a project with defaults" do
      assert {:ok, project} =
               Projects.create_project(%{"name" => "Cache", "visibility" => "public"})

      assert project.name == "Cache"
      assert project.visibility == :public
    end

    test "requires a name" do
      assert {:error, changeset} = Projects.create_project(%{"visibility" => "public"})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_project/2" do
    test "updates the description" do
      {:ok, project} =
        Projects.create_project(%{"name" => "Server", "visibility" => "public"})

      {:ok, updated} = Projects.update_project(project, %{"description" => "The API"})
      assert updated.description == "The API"
    end
  end

  describe "delete_project/1" do
    test "removes the project" do
      {:ok, project} =
        Projects.create_project(%{"name" => "Gone", "visibility" => "public"})

      assert {:ok, _} = Projects.delete_project(project)
      assert Projects.list_projects() == []
    end
  end
end
