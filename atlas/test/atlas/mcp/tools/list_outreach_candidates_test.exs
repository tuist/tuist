defmodule Atlas.MCP.Tools.ListOutreachCandidatesTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.ListOutreachCandidates

  test "lists Atlas-owned candidates" do
    candidate = insert_outreach_candidate!()

    assert {:ok, %{count: 1, candidates: [listed]}} =
             execute_tool(ListOutreachCandidates, mcp_conn(nil), %{"status" => "pending"})

    assert listed.id == candidate.id
    assert listed.search_segment == "mobile_mid_large"
  end
end
