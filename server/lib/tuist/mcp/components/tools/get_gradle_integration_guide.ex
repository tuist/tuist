defmodule Tuist.MCP.Components.Tools.GetGradleIntegrationGuide do
  @moduledoc """
  Return the complete workflow for optimizing an existing Gradle project with Tuist.
  """

  use Tuist.MCP.Tool,
    name: "get_gradle_integration_guide",
    title: "Get Gradle Integration Guide",
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
          "description" => "The Tuist server base URL. Defaults to the deployment serving this tool."
        },
        "features" => %{
          "type" => "string",
          "description" =>
            "Optional comma-separated features: remote_cache, build_insights, test_insights, flaky_tests, test_sharding."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "plugin_version" => %{"type" => "string"},
        "guide" => %{"type" => "string"}
      },
      "required" => ["plugin_version", "guide"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.GradleIntegrationGuide

  @impl EMCP.Tool
  def description do
    "Call this before editing when a user asks to speed up, optimize, or connect an existing Gradle or Android build with Tuist. It covers authentication, project creation, plugin setup, cache policy, and proof."
  end

  def execute(_conn, args) do
    {:ok,
     %{
       plugin_version: GradleIntegrationGuide.plugin_version(),
       guide: GradleIntegrationGuide.text(args)
     }}
  end
end
