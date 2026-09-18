defmodule Atlas.MCP.Tools.ResolveErrorIssueTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.ResolveErrorIssue
  alias Atlas.Repo

  test "marks an issue as resolved" do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
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

    user = insert_user!()

    {:ok, %{"issue" => payload}} =
      execute_tool(ResolveErrorIssue, mcp_conn(user), %{"id" => issue.id})

    assert payload.status == "resolved"
    {:ok, refetched} = Errors.fetch_issue(issue.id)
    assert refetched.status == :resolved
  end

  test "returns an error when the issue does not exist" do
    user = insert_user!()

    assert {:error, "Error issue not found."} =
             execute_tool(ResolveErrorIssue, mcp_conn(user), %{
               "id" => "00000000-0000-0000-0000-000000000000"
             })
  end
end
