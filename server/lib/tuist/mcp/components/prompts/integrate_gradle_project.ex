defmodule Tuist.MCP.Components.Prompts.IntegrateGradleProject do
  @moduledoc """
  Guides you through integrating Tuist into an existing Gradle project.
  """

  use Tuist.MCP.Prompt,
    name: "integrate_gradle_project",
    arguments: [
      %{name: "account_handle", description: "The Tuist account or organization handle."},
      %{name: "project_handle", description: "The Tuist project handle."},
      %{
        name: "features",
        description:
          "Optional comma-separated feature list. Supported values: remote_cache, build_insights, test_insights, flaky_tests, test_sharding."
      }
    ]

  @impl EMCP.Prompt
  def description, do: "Guides you through integrating Tuist into an existing Gradle project."

  @impl EMCP.Prompt
  def template(_conn, args) do
    %{
      messages: [
        Tuist.MCP.Prompt.message(Tuist.MCP.GradleIntegrationGuide.text(args))
      ]
    }
  end
end
