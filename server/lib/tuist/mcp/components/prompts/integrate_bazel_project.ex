defmodule Tuist.MCP.Components.Prompts.IntegrateBazelProject do
  @moduledoc """
  Guides you through integrating Tuist into an existing Bazel project.
  """

  use Tuist.MCP.Prompt,
    name: "integrate_bazel_project",
    arguments: [
      %{name: "account_handle", description: "The Tuist account or organization handle."},
      %{name: "project_handle", description: "The Tuist project handle."},
      %{name: "server_url", description: "The Tuist HTTP or HTTPS server origin."}
    ]

  alias Tuist.MCP.BazelIntegrationGuide

  @impl EMCP.Prompt
  def description, do: "Guides you through integrating Tuist into an existing Bazel project."

  @impl EMCP.Prompt
  def template(_conn, args) do
    text =
      case BazelIntegrationGuide.build(args) do
        {:ok, guide} ->
          guide

        {:error, message} ->
          "The Bazel integration guide could not be generated: #{message} Do not edit files or run authentication commands until the user supplies a valid server origin."
      end

    %{messages: [Tuist.MCP.Prompt.message(text)]}
  end
end
