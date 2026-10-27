defmodule Atlas.MCP.Tools.RotateAutomationWebhookCredential do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "rotate_automation_webhook_credential",
    schema: Atlas.MCP.Automation.schema(:rotate_trigger),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description,
    do:
      "Rotate an execution-owner webhook bearer credential. The old credential immediately stops working; the new secret is returned once and must never be logged or saved as an ordinary behavior/workflow input. Schedules cannot rotate credentials."

  def execute(conn, args), do: Automation.execute(:rotate_trigger, conn, args)
end
