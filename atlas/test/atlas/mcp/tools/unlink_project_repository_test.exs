defmodule Atlas.MCP.Tools.UnlinkProjectRepositoryTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Domains.GitHubRepository
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.UnlinkProjectRepository
  alias Atlas.Repo

  test "unlinks a repository from a project" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})

    {:ok, _domain} =
      Domains.create_domain(%{
        "name" => "Cache",
        "project_id" => project.id,
        "github_repository_owner" => "tuist",
        "github_repository_name" => "atlas"
      })

    repository = Repo.get_by!(GitHubRepository, owner: "tuist", name: "atlas")
    user = insert_user!()

    {:ok, %{"project" => payload_project, "unlinked_repository" => payload_repository}} =
      execute_tool(UnlinkProjectRepository, mcp_conn(user), %{
        "project_id" => project.id,
        "repository_id" => repository.id
      })

    refute "tuist/atlas" in payload_project["repositories"]
    assert payload_repository["id"] == repository.id
    assert Repo.get(GitHubRepository, repository.id) == nil
  end

  test "returns an error when the project does not exist" do
    user = insert_user!()

    assert {:error, "Project or repository not found."} =
             execute_tool(UnlinkProjectRepository, mcp_conn(user), %{
               "project_id" => "00000000-0000-0000-0000-000000000000",
               "repository_id" => "00000000-0000-0000-0000-000000000000"
             })
  end
end
