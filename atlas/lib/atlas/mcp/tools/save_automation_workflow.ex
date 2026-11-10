defmodule Atlas.MCP.Tools.SaveAutomationWorkflow do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "save_automation_workflow",
    schema: Atlas.MCP.Automation.schema(:save),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Create or edit a workflow by ID. Source is a JSON plan or a JavaScript function body returning a plan. Use publish: true to validate and atomically save a published version, optionally with expected_revision_id to reject stale edits. Otherwise save an unpublished draft. Saving never executes the workflow; existing runs and triggers keep their versions."

  def execute(conn, args), do: Automation.execute(:save, conn, args)
end
