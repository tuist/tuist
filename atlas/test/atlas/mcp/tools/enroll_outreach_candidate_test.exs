defmodule Atlas.MCP.Tools.EnrollOutreachCandidateTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.EnrollOutreachCandidate
  alias Atlas.Outreach.Candidate
  alias Atlas.Repo

  test "enrolls an Atlas-owned candidate" do
    actor = insert_user!()
    candidate = insert_outreach_candidate!(%{full_name: "Riley Stone"})

    assert {:ok, contact} =
             execute_tool(
               EnrollOutreachCandidate,
               mcp_conn(actor),
               %{"candidate_id" => candidate.id}
             )

    assert contact.full_name == "Riley Stone"
    assert Repo.get!(Candidate, candidate.id).status == "enrolled"
  end
end
