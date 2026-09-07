defmodule Tuist.MCP.Components.Tools.GetBazelIntegrationGuide do
  @moduledoc """
  Return the complete workflow for connecting an existing Bazel project to Tuist.
  """

  use Tuist.MCP.Tool,
    name: "get_bazel_integration_guide",
    title: "Get Bazel Integration Guide",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The Tuist account handle, when already known."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The Tuist project handle, when already known."
        },
        "server_url" => %{
          "type" => "string",
          "description" => "The Tuist HTTP or HTTPS server origin. Defaults to the deployment serving this tool."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "guide" => %{"type" => "string"}
      },
      "required" => ["guide"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.BazelIntegrationGuide

  @impl EMCP.Tool
  def description do
    "Return the workflow for connecting an existing Bazel project to Tuist. Use when the user asks to connect, configure, or debug that build. Covers project creation, authentication, setup, and verification."
  end

  def execute(_conn, args) do
    case BazelIntegrationGuide.build(args) do
      {:ok, guide} -> {:ok, %{guide: guide}}
      {:error, message} -> {:error, message}
    end
  end
end
