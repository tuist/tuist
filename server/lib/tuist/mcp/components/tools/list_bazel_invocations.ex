defmodule Tuist.MCP.Components.Tools.ListBazelInvocations do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "list_bazel_invocations",
    title: "List Bazel Invocations",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "status" => %{"type" => "string", "enum" => ["success", "failure"], "description" => "Filter by status."},
        "git_branch" => %{"type" => "string", "description" => "Filter by git branch."},
        "git_commit_sha" => %{"type" => "string", "description" => "Filter by full git commit SHA."},
        "is_ci" => %{"type" => "boolean", "description" => "Filter by whether the invocation ran on CI."},
        "command" => %{"type" => "string", "description" => "Filter by Bazel command, for example build or test."},
        "page" => %{"type" => "integer", "description" => "Page number, defaulting to 1."},
        "page_size" => %{"type" => "integer", "description" => "Results per page, up to 100."}
      },
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "invocations" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.BazelInvocation.schema()},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["invocations", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.BazelInvocation
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description do
    "List Bazel invocations for a project, newest first, with custom metadata, build metrics, bounded timeline and critical-path diagnostics, and correlated remote-cache totals. Filter by status, git branch, commit SHA, CI and command; status failure, a git_branch and page_size 1 return the latest failing invocation on that branch."
  end

  def execute(_conn, args, project) do
    {invocations, meta} =
      Bazel.list_project_invocations(project.id, %{
        status: args["status"],
        git_branch: args["git_branch"],
        git_commit_sha: args["git_commit_sha"],
        is_ci: args["is_ci"],
        command: args["command"],
        page: MCPTool.page(args),
        page_size: MCPTool.page_size(args)
      })

    {:ok,
     %{
       invocations: Enum.map(invocations, &BazelInvocation.json/1),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end
end
