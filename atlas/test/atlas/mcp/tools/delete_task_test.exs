defmodule Atlas.MCP.Tools.DeleteTaskTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.DeleteTask
  alias Atlas.Tasks

  test "only authenticated teammates can delete a shared task" do
    user = insert_user!()
    other = insert_user!()
    {:ok, task} = Tasks.create_task(%{title: "Delete via MCP", assignee_id: user.id}, user)
    assert {:error, _reason} = execute_tool(DeleteTask, mcp_conn(nil), %{"task_id" => task.id})
    assert {:error, "Task not found."} = execute_tool(DeleteTask, mcp_conn(other), %{"task_id" => "invalid"})
    assert {:ok, %{deleted: true}} = execute_tool(DeleteTask, mcp_conn(other), %{"task_id" => task.id})
    assert Tasks.get_task(task.id) == nil
  end
end
