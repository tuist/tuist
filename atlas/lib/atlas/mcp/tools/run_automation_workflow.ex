defmodule Atlas.MCP.Tools.RunAutomationWorkflow do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "run_automation_workflow",
    schema: Atlas.MCP.Automation.schema(:run),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Queue a published workflow with validated inputs, running as the caller. Supply both revision_id and a stable UUID request_id to pin the reviewed contract and safely replay an uncertain admission; reuse only with identical workflow, revision and inputs. Omit both to run the current revision without deduplication. May create records; only invoke when execution is requested."

  def execute(conn, args), do: Automation.execute(:run, conn, args)
end
