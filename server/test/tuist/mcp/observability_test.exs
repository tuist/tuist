defmodule Tuist.MCP.ObservabilityTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.MCP.Observability
  alias Tuist.Projects.Project

  test "records the authorized target account and project" do
    parent = self()

    expect(OpenTelemetry.Tracer, :set_attribute, 2, fn key, value ->
      send(parent, {:trace_attribute, key, value})
      :ok
    end)

    project = %Project{name: "atlas", account: %Account{name: "tuist"}}

    Observability.set_project_context(project)

    assert Logger.metadata()[:mcp_account_handle] == "tuist"
    assert Logger.metadata()[:mcp_project_handle] == "atlas"
    assert_receive {:trace_attribute, "mcp.account.handle", "tuist"}
    assert_receive {:trace_attribute, "mcp.project.handle", "atlas"}
  end

  test "records the tool name" do
    expect(OpenTelemetry.Tracer, :set_attribute, fn "mcp.tool.name", "list_projects" ->
      :ok
    end)

    Observability.set_tool_context("list_projects")

    assert Logger.metadata()[:mcp_tool_name] == "list_projects"
  end

  test "does not fail when the project account is not preloaded" do
    reject(&OpenTelemetry.Tracer.set_attribute/2)

    Observability.set_project_context(%Project{name: "atlas"})

    refute Keyword.has_key?(Logger.metadata(), :mcp_account_handle)
    refute Keyword.has_key?(Logger.metadata(), :mcp_project_handle)
  end
end
