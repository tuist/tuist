defmodule Atlas.MCP.Tools.GetAutomationAnalytics do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "get_automation_analytics",
    schema: Atlas.MCP.Automation.schema(:analytics),
    output_schema: Atlas.MCP.Automation.output_schema()

  alias Atlas.MCP.Automation

  def description do
    "Read execution metrics and daily chart points for 1–90 UTC days (default 30), optionally scoped to a workflow across all its revisions. end_date is an optional ISO date, not later than today. Cohorts use execution start dates and current statuses. Success rate includes failed, rejected, and cancelled finished runs; unfinished runs are excluded. Completion time includes queueing, retries, and approval waits. Missing rates/durations are null, not zero. Includes the preceding period for comparisons."
  end

  def execute(conn, args), do: Automation.execute(:analytics, conn, args)
end
