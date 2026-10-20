defmodule Atlas.MCP.Tools.ListErrorIssuesTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.ListErrorIssues
  alias Atlas.Repo

  test "returns [] when no issues exist" do
    user = insert_user!()
    {:ok, %{"issues" => []}} = execute_tool(ListErrorIssues, mcp_conn(user), %{})
  end

  test "lists issues, filtering by project" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, other} = Projects.create_project(%{"name" => "Other", "visibility" => "public"})
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    {:ok, issue} =
      %Issue{}
      |> Issue.changeset(%{
        project_id: project.id,
        fingerprint: String.duplicate("a", 64),
        title: "Boom",
        first_seen: now,
        last_seen: now
      })
      |> Repo.insert()

    {:ok, _} =
      %Issue{}
      |> Issue.changeset(%{
        project_id: other.id,
        fingerprint: String.duplicate("b", 64),
        title: "Other boom",
        first_seen: now,
        last_seen: now
      })
      |> Repo.insert()

    user = insert_user!()

    {:ok, %{"issues" => issues}} =
      execute_tool(ListErrorIssues, mcp_conn(user), %{"project_id" => project.id})

    ids = Enum.map(issues, & &1.id)
    assert issue.id in ids
    assert length(issues) == 1
  end
end
