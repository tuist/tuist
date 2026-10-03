defmodule Atlas.MCP.Tools.RejectOutreachCandidateTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.RejectOutreachCandidate

  test "rejects an Atlas-owned candidate with a reason" do
    actor = insert_user!()
    candidate = insert_outreach_candidate!()

    assert {:ok, rejected} =
             execute_tool(
               RejectOutreachCandidate,
               mcp_conn(actor),
               %{"candidate_id" => candidate.id, "reason" => "Not a product role"}
             )

    assert rejected.status == "rejected"
    assert rejected.rejection_reason == "Not a product role"
  end
end
