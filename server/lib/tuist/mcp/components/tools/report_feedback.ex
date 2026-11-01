defmodule Tuist.MCP.Components.Tools.ReportFeedback do
  @moduledoc """
  Lets agents tell the Tuist team when the MCP server did not behave as they expected.
  """

  use Tuist.MCP.Tool,
    name: "report_feedback",
    title: "Report Feedback",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "properties" => %{
        "tool_name" => %{
          "type" => "string",
          "pattern" => "^[a-z0-9_]{1,100}$",
          "description" => "The Tuist MCP tool or prompt the feedback is about, if any."
        },
        "category" => %{
          "type" => "string",
          "enum" => ["unexpected_result", "error", "missing_data", "missing_capability", "unclear_description", "other"],
          "description" => "The kind of problem."
        },
        "expected" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 3000,
          "description" => "What you expected to happen or to be able to do."
        },
        "actual" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 3000,
          "description" => "What actually happened, including relevant error messages."
        },
        "suggestion" => %{
          "type" => "string",
          "maxLength" => 3000,
          "description" => "Optional change to the tool, its parameters, or its output that would have helped."
        }
      },
      "required" => ["category", "expected", "actual"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "feedback_id" => %{"type" => "string"}
      },
      "required" => ["feedback_id"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Feedback

  @impl EMCP.Tool
  def description do
    "Report to the Tuist team when a Tuist MCP tool or prompt did not work the way you expected: " <>
      "a confusing or wrong result, an error, missing data, an unclear parameter, or a capability you " <>
      "needed but could not find. Do not report mistakes in your own arguments or missing permissions. " <>
      "Send one report per distinct problem. The report opens a conversation with Tuist support, who may " <>
      "reply to the user by email, so tell the user you sent it. Do not include source code, secrets, " <>
      "or personal data."
  end

  def execute(conn, arguments) do
    Feedback.report(arguments, Authorization.authenticated_subject(conn.assigns))
  end
end
