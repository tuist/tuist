defmodule Atlas.MCP.Tools.CreateTaskTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.CreateTask

  test "creates a task for the caller with a valid structured response" do
    user = insert_user!()

    assert {:ok, %{task: task}} =
             execute_tool(CreateTask, mcp_conn(user), %{"title" => "Review proposal"})

    assert task.title == "Review proposal"
    assert task.assignee_id == user.id
    assert task.remind_at == nil
  end
end
