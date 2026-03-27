defmodule Tuist.MCP.Components.Tools.GetBundleArtifactTree do
  @moduledoc """
  Get the full artifact tree for a bundle as a flat list sorted by path. The bundle_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/bundles/{id}.
  """

  use Tuist.MCP.Tool,
    name: "get_bundle_artifact_tree",
    schema: %{
      "type" => "object",
      "properties" => %{
        "bundle_id" => %{
          "type" => "string",
          "description" => "The ID of the bundle."
        }
      },
      "required" => ["bundle_id"]
    }

  alias Tuist.Bundles
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Get the full artifact tree for a bundle as a flat list sorted by path. The bundle_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/bundles/{id}."

  def execute(conn, %{"bundle_id" => bundle_id}) do
    with {:ok, _, _} <-
           MCPTool.load_and_authorize(
             Bundles.get_bundle(bundle_id),
             conn.assigns,
             :read,
             :bundle,
             "Bundle not found: #{bundle_id}"
           ) do
      artifacts = Bundles.get_bundle_artifact_tree(bundle_id)

      {:ok,
       %{
         bundle_id: bundle_id,
         artifacts:
           Enum.map(artifacts, fn artifact ->
             %{
               artifact_type: to_string(artifact.artifact_type),
               path: artifact.path,
               size: artifact.size
             }
           end)
       }}
    end
  end
end
